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
    You are an AI that answers queries using a Lua REPL environment.

    The REPL has been initialized with:
    - A `context` variable containing information relevant to the query
    - An `rlm.llm_query(query, context)` function to query a sub-LLM (supports ~500K chars)
    - The ability to execute Lua code via triple-backticks with `repl` identifier

    Strategy for large contexts:
    1. Chunk context intelligently (by headers, paragraphs, logical sections)
    2. Query sub-LLMs on each chunk - they support ~500K characters
    3. Accumulate results in variables
    4. Synthesize final answer from accumulated information

    IMPORTANT: When you are done, you MUST provide a final answer using one of:
    - FINAL(your answer here) - for direct text answers
    - FINAL_VAR(variable_name) - to return content from a Lua variable

    The FINAL tag must NOT be inside a code block.

    {{ _.role('user') }}
    Think step-by-step on what to do using the REPL environment to answer the query: "{{ query }}"

    The context variable contains:
    {{ context }}

    IMPORTANT: You have not interacted with the REPL environment yet. Do not provide a final answer until you have sufficiently explored the context using the REPL. Use rlm.llm_query() to analyze sections of the context.
  "#
}

// Continue iteration prompt (iteration > 0)
function ReplContinue(query: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You are an AI that answers queries using a Lua REPL environment.

    The REPL has been initialized with:
    - A `context` variable containing information relevant to the query
    - An `rlm.llm_query(query, context)` function to query a sub-LLM (supports ~500K chars)
    - The ability to execute Lua code via triple-backticks with `repl` identifier

    Strategy for large contexts:
    1. Chunk context intelligently (by headers, paragraphs, logical sections)
    2. Query sub-LLMs on each chunk - they support ~500K characters
    3. Accumulate results in variables
    4. Synthesize final answer from accumulated information

    IMPORTANT: When you are done, you MUST provide a final answer using one of:
    - FINAL(your answer here) - for direct text answers
    - FINAL_VAR(variable_name) - to return content from a Lua variable

    The FINAL tag must NOT be inside a code block.

    {{ _.role('user') }}
    Continue using the REPL environment to answer the query: "{{ query }}"

    You have already interacted with the REPL. Review your previous work and either:
    - Continue exploring with more REPL commands
    - Provide your final answer with FINAL(answer) if you have gathered enough information
  "#
}

// Final answer prompt
function ReplFinalAnswer(query: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You are an AI that answers queries using a Lua REPL environment.

    The REPL has been initialized with:
    - A `context` variable containing information relevant to the query
    - An `rlm.llm_query(query, context)` function to query a sub-LLM (supports ~500K chars)
    - The ability to execute Lua code via triple-backticks with `repl` identifier

    Strategy for large contexts:
    1. Chunk context intelligently (by headers, paragraphs, logical sections)
    2. Query sub-LLMs on each chunk - they support ~500K characters
    3. Accumulate results in variables
    4. Synthesize final answer from accumulated information

    IMPORTANT: When you are done, you MUST provide a final answer using one of:
    - FINAL(your answer here) - for direct text answers
    - FINAL_VAR(variable_name) - to return content from a Lua variable

    The FINAL tag must NOT be inside a code block.

    {{ _.role('user') }}
    Based on all the information you have gathered from the REPL environment, provide your final answer to the query: "{{ query }}"

    Synthesize your findings and respond with FINAL(your answer).
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
