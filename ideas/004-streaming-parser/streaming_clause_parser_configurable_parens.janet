#!/usr/bin/env janet

# Stateful streaming clause parser with configurable wrapper skipping.
#
# Mirrors streaming_clause_parser_configurable_parens.py:
# - clauses split on comma and period
# - decimal-safe period handling, so 3.14 stays in one clause
# - optional skipping of wrapped content in () and {}
# - unclosed wrapper text is recovered at end of stream

(def chunks
  @["The value is 3."
    "14, keep this (drop this part."
    " still inside (nested, still hidden)), then continue."
    " Another clause (ignore"
    " me, even with (deep, nested) commas.) ends here."
    " Last one (outer (inner"
    " with 9.99, and commas.) still outer) done."
    " Curly demo {hide this, and this."
    " still hidden} visible again."
    " Mixed {(nested braces, and parens)} final clause."
    " Unclosed case starts (keep this text, even with commas"
    " and 7.5 as-is"])

(def byte-comma 44)
(def byte-dot 46)
(def byte-lparen 40)
(def byte-rparen 41)
(def byte-lbrace 123)
(def byte-rbrace 125)
(def eof ::eof)

(defn digit? [ch]
  (and (number? ch) (>= ch 48) (<= ch 57)))

(defn normalize-whitespace [text]
  (string/join
    (filter |(not (empty? $))
      (string/split " " (string/trim text)))
    " "))

(defn start-chunk-producer
  "Start an async producer that sends chunks through a channel."
  [chunks chunk-chan &opt interval-s]
  (default interval-s 0.05)
  (ev/go
    (fn []
      (each chunk chunks
        (ev/sleep interval-s)
        (printf "chunk arrived: %q" chunk)
        (ev/give chunk-chan chunk))
      (ev/give chunk-chan eof))))

(defn clause-generator
  "Return a coroutine that yields clauses as chunks arrive."
  [chunk-chan &opt skip-wrapped]
  (default skip-wrapped true)

  (coro
    (def pending (buffer/new 0))
    (def skipped-wrapped-buffer (buffer/new 0))
    (var paren-depth 0)
    (var brace-depth 0)
    (var pending-dot-after-digit false)

    (defn emit-pending []
      (def clause (normalize-whitespace (string pending)))
      (when (not (empty? clause))
        (yield clause))
      (buffer/clear pending))

    (while true
      (def chunk (ev/take chunk-chan))
      (when (= chunk eof)
        (break))
      (each ch chunk
          # Resolve ambiguous "digit + ." once the next byte arrives.
          (when pending-dot-after-digit
            (if (digit? ch)
              (buffer/push pending byte-dot)
              (emit-pending))
            (set pending-dot-after-digit false))

          (var consumed-by-wrapper false)

          # Optional wrapper stripping with cross-chunk depth tracking.
          (when skip-wrapped
            (def in-wrapper (or (> paren-depth 0) (> brace-depth 0)))
            (cond
              (= ch byte-lparen)
              (do
                (when (not in-wrapper)
                  (buffer/clear skipped-wrapped-buffer))
                (set paren-depth (+ paren-depth 1))
                (buffer/push skipped-wrapped-buffer ch)
                (set consumed-by-wrapper true))

              (= ch byte-lbrace)
              (do
                (when (not in-wrapper)
                  (buffer/clear skipped-wrapped-buffer))
                (set brace-depth (+ brace-depth 1))
                (buffer/push skipped-wrapped-buffer ch)
                (set consumed-by-wrapper true))

              in-wrapper
              (do
                (buffer/push skipped-wrapped-buffer ch)
                (cond
                  (and (= ch byte-rparen) (> paren-depth 0))
                  (set paren-depth (- paren-depth 1))

                  (and (= ch byte-rbrace) (> brace-depth 0))
                  (set brace-depth (- brace-depth 1)))

                # Balanced wrapper: permanently drop buffered wrapped text.
                (when (and (= paren-depth 0) (= brace-depth 0))
                  (buffer/clear skipped-wrapped-buffer))
                (set consumed-by-wrapper true))))

          (unless consumed-by-wrapper
            (cond
              (= ch byte-comma)
              (emit-pending)

              (= ch byte-dot)
              (do
                (def prev-ch
                  (if (> (length pending) 0)
                    (get pending (- (length pending) 1))
                    nil))
                (if (digit? prev-ch)
                  (set pending-dot-after-digit true)
                  (emit-pending)))

              :else
              (buffer/push pending ch)))))

    # If stream ends with unclosed wrappers, keep remaining buffered text.
    (when (and skip-wrapped (or (> paren-depth 0) (> brace-depth 0)))
      (buffer/push pending skipped-wrapped-buffer))

    # Finalization pass.
    (when pending-dot-after-digit
      (emit-pending)
      (set pending-dot-after-digit false))

    (def tail (normalize-whitespace (string pending)))
    (when (not (empty? tail))
      (yield tail))))

(print "Config: skip-wrapped=true\n")
(def chunk-chan (ev/chan))
(start-chunk-producer chunks chunk-chan)
(def parser (clause-generator chunk-chan true))
(def clauses @[])

(each clause parser
  (printf "clause parsed: %q" clause)
  (array/push clauses clause))

(print "\nAll parsed clauses:")
(var idx 1)
(each clause clauses
  (print idx ". " clause)
  (set idx (+ idx 1)))
