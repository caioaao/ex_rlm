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

    IMPORTANT: Your response must be ONLY valid Lua code. No markdown, no explanations outside of Lua comments.

    Available in the Lua environment:
    - `context` - variable containing information relevant to the query
    - `rlm.llm_query(query, context)` - query a sub-LLM (supports ~500K chars)
    - `rlm.answer(value)` - return your final answer

    Strategy for large contexts:
    1. Chunk context intelligently (by headers, paragraphs, logical sections)
    2. Query sub-LLMs on chunks using rlm.llm_query()
    3. Accumulate results in variables
    4. When ready, call: return rlm.answer("your final answer")

    You can also return a variable's value: return rlm.answer(my_result_variable)

    Use Lua comments (-- comment) to explain your reasoning.

    {{ _.role('user') }}
    Write Lua code to answer the query: "{{ query }}"

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

    IMPORTANT: Your response must be ONLY valid Lua code. No markdown, no explanations outside of Lua comments.

    Available in the Lua environment:
    - `context` - variable containing information relevant to the query
    - `rlm.llm_query(query, context)` - query a sub-LLM (supports ~500K chars)
    - `rlm.answer(value)` - return your final answer
    - All variables from previous iterations are still available

    Use Lua comments (-- comment) to explain your reasoning.

    {{ _.role('user') }}
    Continue writing Lua code to answer the query: "{{ query }}"

    Review your previous work and either:
    - Continue exploring with more Lua code
    - Call return rlm.answer("your answer") if you have gathered enough information
  "#
}

// Final answer prompt
function ReplFinalAnswer(query: string) -> string {
  client GPT4o
  prompt #"
    {{ _.role('system') }}
    You are an AI that answers queries using a Lua REPL environment.

    IMPORTANT: Your response must be ONLY valid Lua code. No markdown, no explanations outside of Lua comments.

    Available in the Lua environment:
    - `context` - variable containing information relevant to the query
    - `rlm.answer(value)` - return your final answer
    - All variables from previous iterations are still available

    {{ _.role('user') }}
    Based on all the information you have gathered from the REPL environment, provide your final answer to the query: "{{ query }}"

    You MUST call return rlm.answer("your answer") now. Synthesize your findings into a final answer.
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
