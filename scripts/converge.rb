#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "time"

def usage
  puts <<~EOF
    converge.rb - run rotating agent loop with optional session artifacts and handoff

    USAGE
      converge.rb [--session-dir <path>] --prompt-list <path> --agent-cmd "<command>" [--agent-cmd "<command>" ...] [--max-steps <n>] [--tmux] [--tmux-session-name <name>] [--handoff | --no-handoff]

    REQUIRED
      --prompt-list   File with one prompt path per line (rotation order).
      --agent-cmd     Agent command, e.g. "codex exec" or "claude".
                      Repeat to rotate commands independently from prompts.

    OPTIONAL
      --session-dir   Session root for run artifacts.
      --max-steps     Number of loop iterations (default: 10).
      --tmux          Run each step in a tmux window for live observability.
      --tmux-session-name
                      Optional tmux session name override.
      --handoff       Force handoff artifacts on. Requires --session-dir.
      --no-handoff    Disable handoff artifacts.
      -h, --help      Show this help message.

    PROMPT LIST RULES
      - Empty lines are ignored.
      - Lines starting with # are ignored.
      - Relative prompt paths are resolved from the prompt-list directory.

    EXAMPLES
      ruby scripts/converge.rb --prompt-list ./prompts.txt --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" --max-steps 2
      ruby scripts/converge.rb --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "claude -p --permission-mode bypassPermissions" --no-handoff
      ruby scripts/converge.rb --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "cursor-agent -p --yolo --trust --approve-mcps" --handoff
  EOF
end

def iso_now
  Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
end

def sanitize_tmux_label(text, fallback, max_len)
  safe = text.to_s.strip.gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/-+/, "-").gsub(/\A-+|-+\z/, "")
  safe = safe[0, max_len]
  safe.nil? || safe.empty? ? fallback : safe
end

def build_tmux_session_name(provided)
  return provided unless provided.to_s.empty?

  "converge-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}-#{Process.pid}"
end

def build_tmux_window_name(step, prompt)
  suffix = sanitize_tmux_label(File.basename(prompt, File.extname(prompt)), "step", 24)
  format("s%03d-%s", step, suffix)
end

def tmux_available?
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
    File.executable?(File.join(dir, "tmux"))
  end
end

def configure_tmux_window(session_name, window_name)
  target = "#{session_name}:#{window_name}"
  system("tmux", "set-option", "-t", target, "remain-on-exit", "on") or exit 1
  system("tmux", "set-option", "-t", target, "automatic-rename", "off") or exit 1
end

def build_tmux_step_command(payload, agent_cmd:, stdout_log: nil, stderr_log: nil)
  command = "printf '%s' #{Shellwords.escape(payload)} | bash -c #{Shellwords.escape(agent_cmd)}"
  if stdout_log && stderr_log
    command += " > >(tee #{Shellwords.escape(stdout_log)}) 2> >(tee #{Shellwords.escape(stderr_log)} >&2)"
  end
  "set -o pipefail; #{command}"
end

def wait_for_tmux_window(session_name, window_name)
  target = "#{session_name}:#{window_name}"
  loop do
    dead = `tmux list-panes -t #{Shellwords.escape(target)} -F '\#{pane_dead}' 2>/dev/null`.strip
    break if dead == "1"

    sleep 0.1
  end
  code = `tmux display-message -p -t #{Shellwords.escape(target)} '\#{pane_dead_status}'`.strip
  Integer(code.empty? ? "1" : code)
end

def build_effective_prompt(step, agent_cmd:, prompt:, input_handoff: nil, output_handoff: nil)
  header = []
  header << "# Runtime Protocol"
  header << ""
  header << "- step: #{step}"
  header << "- agent_cmd: #{agent_cmd}"
  if output_handoff
    if input_handoff
      header << "- input_handoff: #{input_handoff}"
      header << "- read input handoff as latest context."
    else
      header << "- input_handoff: (none)"
      header << "- no previous handoff exists for this step."
    end
    header << "- output_handoff: #{output_handoff}"
    header << "- write next handoff content to output_handoff."
  end
  header << "- do not modify files outside the task scope."
  header << ""
  header << "# Role Prompt"
  header << ""
  header.join("\n") + File.read(prompt)
end

def require_value!(args, index, option, allow_empty: true)
  value = args[index + 1]
  if value.nil?
    warn "Missing value for #{option}"
    usage
    exit 1
  end

  if !allow_empty && value.empty?
    warn "Invalid value for #{option}"
    usage
    exit 1
  end

  value
end

opts = { max_steps: 10, tmux: false, agent_cmds: [], handoff: nil }
i = 0
while i < ARGV.length
  case ARGV[i]
  when "--session-dir" then opts[:session_dir] = require_value!(ARGV, i, "--session-dir"); i += 2
  when "--prompt-list" then opts[:prompt_list] = require_value!(ARGV, i, "--prompt-list"); i += 2
  when "--agent-cmd" then opts[:agent_cmds] << require_value!(ARGV, i, "--agent-cmd", allow_empty: false); i += 2
  when "--max-steps" then opts[:max_steps] = Integer(require_value!(ARGV, i, "--max-steps")); i += 2
  when "--tmux" then opts[:tmux] = true; i += 1
  when "--tmux-session-name" then opts[:tmux_session_name] = require_value!(ARGV, i, "--tmux-session-name"); i += 2
  when "--handoff" then opts[:handoff] = true; i += 1
  when "--no-handoff" then opts[:handoff] = false; i += 1
  when "-h", "--help" then usage; exit 0
  else
    warn "Unknown argument: #{ARGV[i]}"
    usage
    exit 1
  end
end

if opts[:prompt_list].to_s.empty? || opts[:agent_cmds].empty?
  usage
  exit 1
end
if opts[:max_steps] < 1
  warn "--max-steps must be a positive integer."
  exit 1
end
session_dir = opts[:session_dir].to_s.empty? ? nil : File.expand_path(opts[:session_dir])
if opts[:handoff] && session_dir.nil?
  warn "--handoff requires --session-dir."
  exit 1
end
handoff_enabled = opts[:handoff].nil? ? !session_dir.nil? : opts[:handoff]

FileUtils.mkdir_p(session_dir) if session_dir
prompt_list = File.expand_path(opts[:prompt_list])
unless File.file?(prompt_list)
  warn "Prompt list not found: #{prompt_list}"
  exit 1
end

prompt_base = File.dirname(prompt_list)
prompts = []
File.readlines(prompt_list, chomp: true).each do |raw|
  line = raw.rstrip
  next if line.empty? || line.start_with?("#")

  path = line.start_with?("/") ? line : File.join(prompt_base, line)
  path = File.expand_path(path)
  unless File.file?(path)
    warn "Prompt file not found: #{path}"
    exit 1
  end
  prompts << path
end
if prompts.empty?
  warn "Prompt list contains no usable prompt files."
  exit 1
end

run_dir = nil
loop_log = nil
if session_dir
  run_dir = File.join(session_dir, "run")
  loop_dir = File.join(run_dir, "loop")
  loop_log = File.join(loop_dir, "loop.log")
  FileUtils.mkdir_p(loop_dir)
  FileUtils.touch(loop_log)
end

tmux_session_name = nil
tmux_created = false
if opts[:tmux]
  unless tmux_available?
    warn "--tmux requires tmux on PATH."
    exit 1
  end
  tmux_session_name = build_tmux_session_name(opts[:tmux_session_name])
  if system("tmux", "has-session", "-t", tmux_session_name, out: File::NULL, err: File::NULL)
    warn "tmux session already exists: #{tmux_session_name}"
    exit 1
  end
end

puts "Starting agent loop"
puts "session_dir=#{session_dir}" if session_dir
puts "prompt_count=#{prompts.length}"
puts "max_steps=#{opts[:max_steps]}"
if opts[:agent_cmds].length == 1
  puts "agent_cmd=#{opts[:agent_cmds].first}"
else
  puts "agent_cmd_count=#{opts[:agent_cmds].length}"
end
if tmux_session_name
  puts "tmux_session=#{tmux_session_name}"
  puts "tmux_attach_cmd=tmux attach -t #{Shellwords.escape(tmux_session_name)}"
end

1.upto(opts[:max_steps]) do |step|
  prompt = prompts[(step - 1) % prompts.length]
  agent_cmd = opts[:agent_cmds][(step - 1) % opts[:agent_cmds].length]

  input_handoff = nil
  output_handoff = nil
  step_dir = nil
  stdout_log = nil
  stderr_log = nil
  code = nil

  started = Time.now.to_i
  puts "[step #{step}] start prompt=#{File.basename(prompt)} time=#{iso_now}"

  if session_dir
    step_dir = File.join(run_dir, format("s%03d", step))
    FileUtils.mkdir_p(step_dir)
    effective = File.join(step_dir, "effective_prompt.md")
    stdout_log = File.join(step_dir, "stdout.log")
    stderr_log = File.join(step_dir, "stderr.log")
    File.write(stdout_log, "")
    File.write(stderr_log, "")
    if handoff_enabled
      if step > 1
        prev = File.join(run_dir, format("s%03d", step - 1), "handoff.md")
        input_handoff = prev if File.file?(prev)
      end
      output_handoff = File.join(step_dir, "handoff.md")
      File.write(output_handoff, "")
    end
    File.write(
      effective,
      build_effective_prompt(
        step,
        agent_cmd: agent_cmd,
        prompt: prompt,
        input_handoff: input_handoff,
        output_handoff: output_handoff
      )
    )
    unless opts[:tmux]
      File.open(effective, "r") do |input|
        File.open(stdout_log, "w") do |output|
          File.open(stderr_log, "w") do |error|
            system("bash", "-c", agent_cmd, in: input, out: output, err: error)
            code = $?.exitstatus
            File.write(File.join(step_dir, "exit_code.txt"), "#{code}\n")
          end
        end
      end
    end
  end

  if opts[:tmux]
    tmux_cmd = build_tmux_step_command(
      build_effective_prompt(
        step,
        agent_cmd: agent_cmd,
        prompt: prompt,
        input_handoff: input_handoff,
        output_handoff: output_handoff
      ),
      agent_cmd: agent_cmd,
      stdout_log: stdout_log,
      stderr_log: stderr_log
    )
    window_name = build_tmux_window_name(step, prompt)
    if !tmux_created
      system("tmux", "new-session", "-d", "-s", tmux_session_name, "-n", window_name, "bash", "-c", tmux_cmd) or exit 1
      configure_tmux_window(tmux_session_name, window_name)
      tmux_created = true
    else
      system("tmux", "new-window", "-d", "-t", tmux_session_name, "-n", window_name, "bash", "-c", tmux_cmd) or exit 1
      configure_tmux_window(tmux_session_name, window_name)
    end
    code = wait_for_tmux_window(tmux_session_name, window_name)
    File.write(File.join(step_dir, "exit_code.txt"), "#{code}\n") if step_dir
  elsif !session_dir
    reader, writer = IO.pipe
    writer_thread = Thread.new do
      begin
        writer.write(build_effective_prompt(step, agent_cmd: agent_cmd, prompt: prompt))
      rescue Errno::EPIPE
        nil
      ensure
        writer.close
      end
    end
    system("bash", "-c", agent_cmd, in: reader)
    code = $?.exitstatus
    reader.close
    writer_thread.join
  end

  elapsed = Time.now.to_i - started
  puts "[step #{step}] done exit=#{code} elapsed=#{elapsed}s"
  if loop_log
    File.open(loop_log, "a") do |f|
      f.puts("#{iso_now} step=#{step} prompt=#{prompt} agent_cmd=#{Shellwords.escape(agent_cmd)} exit=#{code} elapsed_s=#{elapsed}")
    end
  end
end

puts "Loop finished after #{opts[:max_steps]} steps."
