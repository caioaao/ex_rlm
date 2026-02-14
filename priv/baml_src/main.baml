client<llm> GPT4o {
  provider openai
  options {
    model "gpt-4o"
    api_key env.OPENAI_API_KEY
  }
}

client<llm> GPT4oMini {
  provider openai
  options {
    model "gpt-4o-mini"
    api_key env.OPENAI_API_KEY
  }
}

client<llm> GPT4Turbo {
  provider openai
  options {
    model "gpt-4-turbo"
    api_key env.OPENAI_API_KEY
  }
}

function ReplCompletion(query: string, repl_history: string, remaining: int) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You are tasked with answering a query with associated context. You can access, transform, and analyze this context in a Lua REPL environment that can recursively query sub-LLMs. You will be queried iteratively until you provide a final answer.

    COST MODEL:
    - Lua execution: instant, no cost (even on 100MB+ contexts)
    - LLM roundtrip (generating this response): expensive, limited budget
    - rlm.llm_query(): spawns a subtree of agents (expensive in tokens/latency), uses depth budget (not roundtrips)
    - You have {{ remaining }} roundtrips remaining
    - Goal: Maximize Lua work per roundtrip; use rlm.llm_query() judiciously for synthesis tasks

    IMPORTANT: Your response must be ONLY valid Lua code. Do NOT wrap your code in markdown code blocks (no ```lua or ```). Just output the raw Lua code directly.

    The REPL environment is initialized with:
    - `context` - variable containing information relevant to your query
    - `rlm.llm_query(query, context)` - query a sub-LLM (can handle ~500K chars). Returns (result, error):
      `result, err = rlm.llm_query("query", ctx); if err then print("Error: " .. err) elseif result then return result end`
    - `print(value)` - output values to see in the next iteration
    - `return value` - return your final answer (ends the session)
    - GLOBAL variables persist across roundtrips (assign without `local`: `my_var = value`)
    - LOCAL variables (`local x = ...`) are lost between roundtrips - avoid them for state you need to keep

    IMPORTANT - Luerl limitations (this is an Erlang Lua implementation with restricted stdlib):
    - string.gmatch() and string.gfind() DO NOT EXIST - use string.find() in a loop instead
    - string.gsub() only works with string replacements, NOT replacement functions
    - For pattern-based splitting, use string.find() + string.sub() in a loop
    - Reserved keywords (end, if, then, etc.) cannot be used as unquoted table keys - use ["end"] or rename

    Use print() to output intermediate results for inspection. Use return to provide your final answer.

    Make sure to explicitly look through the context in the REPL before answering your query.

    LEVERAGE LUA: Lua operations are instant and free, even on 100MB+ contexts.

    Available Lua stdlib for exploration:
    - #context → size in bytes
    - string.sub(s, start, end) → extract substring (1-indexed, end is inclusive)
    - string.find(s, pattern) → returns start_pos, end_pos or nil
    - string.find(s, pattern, init) → search starting from position init
    - string.lower(s) / string.upper(s) → case conversion
    - string.match(s, pattern) → returns captured text or nil
    - string.rep(s, n) → repeat string n times
    - string.reverse(s) → reverse a string
    - string.len(s) → same as #s
    - tonumber(s) / tostring(n) → type conversions
    - math.min(), math.max(), math.floor(), math.ceil() → numeric operations
    - table.insert(t, v), table.concat(t, sep), #table → table operations

    Use rlm.llm_query() only when you need LLM reasoning/synthesis that Lua cannot do.

    When you need LLM analysis on large contexts (chunking strategies):
    1. Direct query: Call rlm.llm_query() directly on the context if it fits
    2. Size-based chunking: Split context into fixed-size chunks using string.sub(), query each chunk, accumulate results in a table, then synthesize
    3. Pattern-based splitting: Use string.find() in a loop to split by delimiters (e.g., "\n\n" or "\n#"):
       sections = {}; pos = 1
       while pos <= #context do
         sep = string.find(context, "\n\n", pos)
         if not sep then table.insert(sections, string.sub(context, pos)); break end
         table.insert(sections, string.sub(context, pos, sep-1)); pos = sep + 2
       end

    IMPORTANT - Chunking efficiency:
    - rlm.llm_query() spawns a subtree of agents (expensive in tokens/latency) but doesn't consume your roundtrip budget
    - Aim for 10-50 chunks maximum to keep sub-query costs reasonable
    - For 500K-10M contexts: use ~20 chunks of ~500K each
    - For 10M+ contexts: use hierarchical summarization (summarize groups of chunks, then summarize summaries)
    - Formula: chunk_size = math.ceil(#context / 20)

    Use Lua comments (-- comment) to explain your reasoning.

    {{ _.role('user') }}
    IMPORTANT: Do not provide a final answer until you have sufficiently explored the context.

    Plan your exploration, then execute multiple operations in one Lua block to answer: "{{ query }}"

    BATCH YOUR EXPLORATION: The context is in the `context` variable. Combine multiple operations in one Lua block:

    -- ANTI-PATTERN (wastes 3 roundtrips):
    -- Roundtrip 1: size = #context; print(size)
    -- Roundtrip 2: preview = string.sub(context, 1, 500); print(preview)
    -- Roundtrip 3: string.find(context, "keyword")

    -- EFFICIENT (1 roundtrip):
    size = #context
    head = string.sub(context, 1, 500)
    tail = string.sub(context, #context - 500)
    pos = string.find(context, "important")
    print("Size:", size, "| Keyword at:", pos or "not found")
    print("Head:", head)
    print("Tail:", tail)

    The history below shows your previous roundtrips:
    {{ repl_history }}

    Your next action:
  "#
}

// Final answer prompt
function ReplFinalAnswer(query: string, repl_history: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You must now provide your final answer using the Lua REPL environment.

    IMPORTANT: Your response must be ONLY valid Lua code. Do NOT wrap your code in markdown code blocks (no ```lua or ```). Just output the raw Lua code directly.

    Available in the Lua environment:
    - `context` - variable containing information relevant to the query
    - `rlm.llm_query(query, context)` - query a sub-LLM. Returns (result, error):
      `result, err = rlm.llm_query("query", ctx); if err then print("Error: " .. err) elseif result then return result end`
    - `print(value)` - output values for debugging
    - `return value` - return your final answer (ends the session)
    - GLOBAL variables persist across roundtrips (assign without `local`: `my_var = value`)
    - LOCAL variables (`local x = ...`) are lost between roundtrips

    Example - synthesize accumulated results:
    local combined = table.concat(results, "\n\n")
    return "Based on my analysis: " .. combined

    {{ _.role('user') }}
    Based on all the information you have gathered from the REPL environment, provide your final answer to the query: "{{ query }}"

    You MUST return your final answer now. Synthesize your findings into a coherent final answer using: return "your answer"

    Previous roundtrips:
    {{ repl_history }}
  "#
}
