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

function ReplCompletion(query: string, repl_history: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You are tasked with answering a query with associated context. You can access, transform, and analyze this context in a Lua REPL environment that can recursively query sub-LLMs. You will be queried iteratively until you provide a final answer.

    IMPORTANT: Your response must be ONLY valid Lua code. Do NOT wrap your code in markdown code blocks (no ```lua or ```). Just output the raw Lua code directly.

    The REPL environment is initialized with:
    - `context` - variable containing information relevant to your query
    - `rlm.llm_query(query, context)` - query a sub-LLM (can handle ~500K chars). Returns (result, error):
      `result, err = rlm.llm_query("query", ctx); if err then print("Error: " .. err) end`
    - `print(value)` - output values to see in the next iteration
    - `return value` - return your final answer (ends the session)
    - GLOBAL variables persist across iterations (assign without `local`: `my_var = value`)
    - LOCAL variables (`local x = ...`) are lost between iterations - avoid them for state you need to keep

    IMPORTANT - Luerl limitations (this is an Erlang Lua implementation with restricted stdlib):
    - string.gmatch() and string.gfind() DO NOT EXIST - use string.find() in a loop instead
    - string.gsub() only works with string replacements, NOT replacement functions
    - For pattern-based splitting, use string.find() + string.sub() in a loop

    Use print() to output intermediate results for inspection. Use return to provide your final answer.

    Make sure to explicitly look through the context in the REPL before answering your query.

    EFFICIENCY: Lua operations are instant and free, rlm.llm_query() calls are expensive.
    Before calling rlm.llm_query(), try Lua string operations first:
    - string.find(context, "pattern") to locate specific text (returns position or nil)
    - string.sub(context, start, end_pos) to extract sections
    - #context for size, string.lower() for case-insensitive matching
    Only use rlm.llm_query() when you need LLM reasoning/synthesis that Lua cannot do.

    Strategies for handling large contexts:
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
    - Each rlm.llm_query() call consumes iteration budget - aim for 10-50 chunks maximum
    - For 500K-10M contexts: use ~20 chunks of ~500K each
    - For 10M+ contexts: use hierarchical summarization (summarize groups of chunks, then summarize summaries)
    - Formula: chunk_size = math.ceil(#context / 20)

    Use Lua comments (-- comment) to explain your reasoning.

    {{ _.role('user') }}
    IMPORTANT: Do not provide a final answer until you have sufficiently explored the context.

    Think step-by-step on what to do using the REPL environment to answer: "{{ query }}"

    The context is available in the `context` Lua variable. Start by exploring it:
    1. Check size: #context
    2. Based on structure, decide how to chunk and analyze

    The history below shows your previous REPL interactions:
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
      `local result, err = rlm.llm_query("query", ctx); if err then print("Error: " .. err) end`
    - `print(value)` - output values for debugging
    - `return value` - return your final answer (ends the session)
    - GLOBAL variables persist across iterations (assign without `local`: `my_var = value`)
    - LOCAL variables (`local x = ...`) are lost between iterations

    Example - synthesize accumulated results:
    local combined = table.concat(results, "\n\n")
    return "Based on my analysis: " .. combined

    {{ _.role('user') }}
    Based on all the information you have gathered from the REPL environment, provide your final answer to the query: "{{ query }}"

    You MUST return your final answer now. Synthesize your findings into a coherent final answer using: return "your answer"

    Previous iterations:
    {{ repl_history }}
  "#
}
