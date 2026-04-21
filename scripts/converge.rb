#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "time"

def usage
  puts <<~EOF
    converge.rb - run rotating agent loop with per-step handoff

    USAGE
      converge.rb --session-dir <path> --prompt-list <path> --agent-cmd "<command>" [--max-steps <n>]

    REQUIRED
      --session-dir   Session root for run artifacts.
      --prompt-list   File with one prompt path per line (rotation order).
      --agent-cmd     Agent command, e.g. "codex exec" or "claude".

    OPTIONAL
      --max-steps     Number of loop iterations (default: 10).
      -h, --help      Show this help message.

    PROMPT LIST RULES
      - Empty lines are ignored.
      - Lines starting with # are ignored.
      - Relative prompt paths are resolved from the prompt-list directory.

    EXAMPLES
      ruby scripts/converge.rb --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" --max-steps 6
      ruby scripts/converge.rb --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "claude -p --permission-mode bypassPermissions"
      ruby scripts/converge.rb --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "cursor-agent -p --yolo --trust --approve-mcps"
  EOF
end

def iso_now
  Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
end

opts = { max_steps: 10 }
i = 0
while i < ARGV.length
  case ARGV[i]
  when "--session-dir" then opts[:session_dir] = ARGV[i + 1]; i += 2
  when "--prompt-list" then opts[:prompt_list] = ARGV[i + 1]; i += 2
  when "--agent-cmd" then opts[:agent_cmd] = ARGV[i + 1]; i += 2
  when "--max-steps" then opts[:max_steps] = Integer(ARGV[i + 1]); i += 2
  when "-h", "--help" then usage; exit 0
  else
    warn "Unknown argument: #{ARGV[i]}"
    usage
    exit 1
  end
end

if opts[:session_dir].to_s.empty? || opts[:prompt_list].to_s.empty? || opts[:agent_cmd].to_s.empty?
  usage
  exit 1
end
if opts[:max_steps] < 1
  warn "--max-steps must be a positive integer."
  exit 1
end

session_dir = File.expand_path(opts[:session_dir])
FileUtils.mkdir_p(session_dir)
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

run_dir = File.join(session_dir, "run")
loop_dir = File.join(run_dir, "loop")
loop_log = File.join(loop_dir, "loop.log")
FileUtils.mkdir_p(loop_dir)
FileUtils.touch(loop_log)

puts "Starting agent loop"
puts "session_dir=#{session_dir}"
puts "prompt_count=#{prompts.length}"
puts "max_steps=#{opts[:max_steps]}"
puts "agent_cmd=#{opts[:agent_cmd]}"

1.upto(opts[:max_steps]) do |step|
  prompt = prompts[(step - 1) % prompts.length]
  step_dir = File.join(run_dir, format("s%03d", step))
  FileUtils.mkdir_p(step_dir)

  input_handoff = nil
  if step > 1
    prev = File.join(run_dir, format("s%03d", step - 1), "handoff.md")
    input_handoff = prev if File.file?(prev)
  end
  output_handoff = File.join(step_dir, "handoff.md")
  effective = File.join(step_dir, "effective_prompt.md")
  stdout_log = File.join(step_dir, "stdout.log")
  stderr_log = File.join(step_dir, "stderr.log")
  exit_file = File.join(step_dir, "exit_code.txt")
  File.write(output_handoff, "")
  File.write(stdout_log, "")
  File.write(stderr_log, "")

  header = []
  header << "# Runtime Protocol"
  header << ""
  header << "- step: #{step}"
  if input_handoff
    header << "- input_handoff: #{input_handoff}"
    header << "- read input handoff as latest context."
  else
    header << "- input_handoff: (none)"
    header << "- no previous handoff exists for this step."
  end
  header << "- output_handoff: #{output_handoff}"
  header << "- write next handoff content to output_handoff."
  header << "- do not modify files outside the task scope."
  header << ""
  header << "# Role Prompt"
  header << ""
  File.write(effective, header.join("\n") + File.read(prompt))

  started = Time.now.to_i
  puts "[step #{step}] start prompt=#{File.basename(prompt)} time=#{iso_now}"

  system("#{opts[:agent_cmd]} < #{Shellwords.escape(effective)} > #{Shellwords.escape(stdout_log)} 2> #{Shellwords.escape(stderr_log)}")
  code = $?.exitstatus
  File.write(exit_file, "#{code}\n")

  elapsed = Time.now.to_i - started
  puts "[step #{step}] done exit=#{code} elapsed=#{elapsed}s"
  File.open(loop_log, "a") do |f|
    f.puts("#{iso_now} step=#{step} prompt=#{prompt} exit=#{code} elapsed_s=#{elapsed}")
  end
end

puts "Loop finished after #{opts[:max_steps]} steps."
