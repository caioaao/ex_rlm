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
    - `rlm.llm_query(query, context)` - query a sub-LLM (can handle ~500K chars)
    - `print(value)` - output values to see in the next iteration
    - `return value` - return your final answer (ends the session)
    - All variables from previous iterations are still available

    Use print() to output intermediate results for inspection. Use return to provide your final answer.

    Make sure to explicitly look through the context in the REPL before answering your query. An example strategy is to first look at the context and figure out a chunking strategy, then break up the context into chunks, query an LLM per chunk with a particular question and save the answers to a buffer, then query an LLM with all the buffers to produce your final answer.

    Strategies for handling large contexts:
    1. Direct query: Call rlm.llm_query() directly on the context if it fits
    2. Size-based chunking: Split context into fixed-size chunks using string.sub(), query each chunk, accumulate results in a table, then synthesize
    3. Header-based splitting: Use string.gmatch() to split by headers/sections, query each section, combine results

    Use Lua comments (-- comment) to explain your reasoning.

    {{ _.role('user') }}
    IMPORTANT: Do not provide a final answer until you have sufficiently explored the context.

    Think step-by-step on what to do using the REPL environment to answer: "{{ query }}"

    The context is available in the `context` Lua variable. Start by exploring it:
    1. Check size: #context
    2. Based on structure, decide how to chunk and analyze

    The history below shows your previous REPL interactions:
    <repl_history>
    {{ repl_history }}
    </repl_history>

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
    - `rlm.llm_query(query, context)` - query a sub-LLM (can handle ~500K chars)
    - `print(value)` - output values for debugging
    - `return value` - return your final answer (ends the session)
    - All variables from previous iterations are still available

    Example - synthesize accumulated results:
    local combined = table.concat(results, "\n\n")
    return "Based on my analysis: " .. combined

    {{ _.role('user') }}
    Based on all the information you have gathered from the REPL environment, provide your final answer to the query: "{{ query }}"

    You MUST return your final answer now. Synthesize your findings into a coherent final answer using: return "your answer"

    Previous iterations:
    <repl_history>
    {{ repl_history }}
    </repl_history>
  "#
}
