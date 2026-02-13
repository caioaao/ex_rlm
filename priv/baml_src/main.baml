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

// First iteration prompt (iteration == 0)
function ReplFirstIteration(query: string, context: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You are tasked with answering a query with associated context. You can access, transform, and analyze this context in a Lua REPL environment that can recursively query sub-LLMs. You will be queried iteratively until you provide a final answer.

    IMPORTANT: Your response must be ONLY valid Lua code. Do NOT wrap your code in markdown code blocks (no ```lua or ```). Just output the raw Lua code directly.

    The REPL environment is initialized with:
    - `context` - variable containing information relevant to your query
    - `rlm.llm_query(query, context)` - query a sub-LLM (can handle ~500K chars)
    - `rlm.answer(value)` - return your final answer

    You will only see truncated outputs from the REPL environment, so you should use rlm.llm_query() on variables you want to analyze. Return the value you want to inspect at the end of your script to see it in the next iteration.

    Make sure to explicitly look through the context in the REPL before answering your query. An example strategy is to first look at the context and figure out a chunking strategy, then break up the context into chunks, query an LLM per chunk with a particular question and save the answers to a buffer, then query an LLM with all the buffers to produce your final answer.

    Strategies for handling large contexts:
    1. Direct query: Call rlm.llm_query() directly on the context if it fits
    2. Size-based chunking: Split context into fixed-size chunks using string.sub(), query each chunk, accumulate results in a table, then synthesize
    3. Header-based splitting: Use string.gmatch() to split by headers/sections, query each section, combine results

    Use Lua comments (-- comment) to explain your reasoning.

    {{ _.role('user') }}
    Write Lua code to answer the query: "{{ query }}"

    The context is available in the `context` Lua variable. Start by exploring it:
    1. Check size: #context
    2. Based on structure, decide how to chunk and analyze

    IMPORTANT: You have not interacted with the REPL environment yet. Do not provide a final answer until you have sufficiently explored the context using the REPL. Think step by step, plan, and execute immediately in your response -- do not just say "I will do this".
  "#
}

// Continue iteration prompt (iteration > 0)
function ReplContinue(query: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You are continuing to answer a query using a Lua REPL environment. You will be queried iteratively until you provide a final answer.

    IMPORTANT: Your response must be ONLY valid Lua code. Do NOT wrap your code in markdown code blocks (no ```lua or ```). Just output the raw Lua code directly.

    Available in the Lua environment:
    - `context` - variable containing information relevant to the query
    - `rlm.llm_query(query, context)` - query a sub-LLM (can handle ~500K chars)
    - `rlm.answer(value)` - return your final answer
    - All variables from previous iterations are still available

    Common patterns:
    - Accumulate: table.insert(results, rlm.llm_query(...))
    - Combine: table.concat(results, "\n")
    - Synthesize: rlm.llm_query("Combine findings", combined)

    {{ _.role('user') }}
    Continue writing Lua code to answer the query: "{{ query }}"

    Review your previous outputs and either:
    - Continue exploring with more Lua code
    - Call return rlm.answer("your answer") if you have gathered enough information

    Think step by step, plan, and execute immediately in your response -- do not just say "I will do this".
  "#
}

// Final answer prompt
function ReplFinalAnswer(query: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You must now provide your final answer using the Lua REPL environment.

    IMPORTANT: Your response must be ONLY valid Lua code. Do NOT wrap your code in markdown code blocks (no ```lua or ```). Just output the raw Lua code directly.

    Available in the Lua environment:
    - `context` - variable containing information relevant to the query
    - `rlm.answer(value)` - return your final answer
    - All variables from previous iterations are still available

    Example - synthesize accumulated results:
    local combined = table.concat(results, "\n\n")
    return rlm.answer("Based on my analysis: " .. combined)

    {{ _.role('user') }}
    Based on all the information you have gathered from the REPL environment, provide your final answer to the query: "{{ query }}"

    You MUST call return rlm.answer("your answer") now. Synthesize your findings into a coherent final answer.
  "#
}

// Simpler function for recursive rlm.llm_query() calls
function LlmQuery(query: string, context: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You are a helpful assistant. Answer the query using the provided context. Be concise and focused.

    {{ _.role('user') }}
    Context:
    {{ context }}

    Query: {{ query }}
  "#
}
