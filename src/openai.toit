// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import certificate_roots
import encoding.json
import http
import net

OPENAI_HOST ::= "api.openai.com"

/**
A client for the OpenAI API.
*/
class Client:
  key_/string
  network_/net.Interface? := ?
  client_/http.Client? := ?
  models_/Models? := null
  headers_/http.Headers? := null

  /**
  Constructs a new client with the given $key.

  Keys are managed here: https://platform.openai.com/account/api-keys.
  */
  constructor --key/string:
    key_ = key
    network_ = net.open
    client_ = http.Client.tls network_
        --root_certificates=[certificate_roots.BALTIMORE_CYBERTRUST_ROOT]

  close:
    if client_:
      client_.close
      client_ = null
    if network_:
      network_.close
      network_ = null

  /**
  Completes the given $prompt with the given $model.

  Use $max_tokens to limit the number of tokens generated.
  Use $stop to specify a list of tokens that will stop the completion.

  Returns the generated text.

  This is a shorthand version of $(complete request).

  Example:
  ```
  client := Client --key=OPENAI_KEY
  text := client.complete --prompt="The quick brown fox jumps over the lazy "
  print text
  ```
  */
  complete --prompt/string --model="davinci" --max_tokens=50 --stop/List?=null -> string:
    request := CompletionRequest
        --model=model
        --prompt=prompt
        --max_tokens=max_tokens
        --stop=stop
    completion := complete request
    choice := completion.choices[0]
    return choice.text

  /**
  Requests a completion for the given $request.
  */
  complete request/CompletionRequest -> Completion:
    response := post_ "/v1/completions" request.to_json
    return Completion.from_json response

  /**
  Completes the given $conversation with the given $model.

  Use $max_tokens to limit the number of tokens generated.
  Use $stop to specify a list of tokens that will stop the completion.

  Returns the generated text.

  This is a shorthand version of $(complete_chat request).

  Example:
  ```
  client := Client --key=OPENAI_KEY
  conversation := [
    ChatMessage.system "You are a helpful assistant that speaks in short sentences.",
    ChatMessage.user "Translate the following sentence to French: 'I have lived there'.",
  ]
  text := client.complete_chat --conversation=conversation
  print text
  ```
  */
  complete_chat --conversation/List --model="gpt-3.5-turbo" --max_tokens=50 --stop/List?=null -> string:
    request := ChatCompletionRequest
        --model=model
        --messages=conversation
        --max_tokens=max_tokens
        --stop=stop
    completion := complete_chat request
    choice/ChatChoice := completion.choices[0]
    return choice.message.content

  /**
  Requests a completion for the given $request.
  */
  complete_chat request/ChatCompletionRequest -> ChatCompletion:
    response := post_ "/v1/chat/completions" request.to_json
    return ChatCompletion.from_json response

  /**
  Returns the $Models object, allowing access to model-related functionality.
  */
  models -> Models:
    if not models_: models_ = Models this
    return models_

  authorization_headers_ -> http.Headers:
    // TODO(florian): switch to saved header once the http library
    // doesn't modify the header anymore.
    // if not headers_:
    //   headers_ = http.Headers
    //   headers_.add "Authorization" "Bearer $key_"
    headers_ = http.Headers
    headers_.add "Authorization" "Bearer $key_"
    return headers_

  post_ path/string payload/Map  -> Map:
    response := client_.post_json payload
        --headers=authorization_headers_
        --host=OPENAI_HOST
        --path=path
    return decode_response_ response

  get_ path/string -> Map:
    response := client_.get
        --headers=authorization_headers_
        --host=OPENAI_HOST
        --path=path
    return decode_response_ response

  decode_response_ response/http.Response -> Map:
    try:
      if response.status_code != 200:
        decoded_object := null
        catch:
          decoded_object = json.decode_stream response.body
        error_object := decoded_object and decoded_object.get "error"
        if not error_object: error_object = {:}
        exception := OpenAIException
            --status_code=response.status_code
            --status_message=response.status_message
            --message=error_object.get "message"
            --type=error_object.get "type"
            --param=error_object.get "param"
            --code=error_object.get "code"
        throw exception
      response_payload := json.decode_stream response.body
      return response_payload
    finally:
      // Drain the body.
      while response.body.read: null

/**
An OpenAI model.
*/
class Model:
  id/string
  object/string
  created/int
  owned_by/string
  permission/List?

  constructor.from_json json/Map:
    id = json["id"]
    object = json["object"]
    created = json["created"]
    owned_by = json["owned_by"]
    permission = json.get "permission"

  stringify -> string:
    return "Model: $id (owned_by $owned_by)"

class Models:
  client_/Client

  constructor .client_:

  list -> List:
    response := client_.get_ "/v1/models"
    return response["data"].map: Model.from_json it

  operator [] id/string -> Model:
    response := client_.get_ "/v1/models/$id"
    return Model.from_json response

class OpenAIException:
  status_code/int
  status_message/string
  message/string?
  type/string?
  param/any
  code/any

  constructor
      --.status_code
      --.status_message
      --.message
      --.type
      --.param
      --.code:

  stringify -> string:
    return "OpenAIException: $status_code - $status_message - $message ($type)"

class CompletionRequest:
  /**
  The ID of the model to use for completion.

  Use $Client.models to get a list of available models, or see
    the [Model overview](https://platform.openai.com/docs/models) for a
    description of each model.
  */
  model/string

  /**
  The prompt(s) to generate completions for.

  The prompt(s) can be a string, an array of strings, an array of tokens, or
    an array of token arrays.

  Default (if not provided): '<|endoftext|>'

  Note that '<|endoftext|>' is the document separator that the model sees during
    training. So if a prompt is not specified the model will generate as if from
    the beginning of a new document.
  */
  prompt/any

  /**
  The maximum number of tokens to generate in the completion.

  The token count of a prompt plus `max_tokens` cannot exceed the model's context length. Most models have a context length of 2048 tokens (except for the newest models, which support 4096).

  Use https://platform.openai.com/tokenizer to see how a text is tokenized. That page also provides
    a way to obtain the token ids for a given text.

  Default: 16
  */
  max_tokens/int?

  /**
  The sampling temperature.

  Higher values, like 0.8 will make the output more random, while lower values, like 0.2 will make
    it more focused and deterministic.

  The temperature must be in the range [0.0, 2.0].
  Default: 1.0.

  We generally recommend altering this or $top_p but not both.

  */
  temperature/float?

  /**
  The probability mass cut-off.

  This is an alternative to sampling with temperature, called nucleus sampling, where the model
    considers the results of the tokens with $top_p probability mass. So 0.1 means only the tokens
    comprising the top 10% probability mass are considered.

  We generally recommend altering this or $temperature but not both.

  The value must be in the range [0.0, 1.0].
  Default: 1.0.
  */
  top_p/float?

  /**
  How many completions to generate for each prompt.

  The value must be in the range [1, 128].
  Default: 1.

  # Warning
  Because this parameter generates many completions, it can quickly consume your token
    quota. Use carefully and ensure that you have reasonable settings for $max_tokens and $stop.
  */
  n/int?

  /**
  Whether to stream back partial progress.

  If set, tokens will be sent as data-only [server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#Event_stream_format)
    as they become available, with the stream terminated by a `data: [DONE]` message.

  Default: false.
  */
  stream/bool?

  /**
  Include the log probabilities on the `logprobs` most likely tokens, as well the chosen tokens.

  For example, if $logprobs is 5, the API will return a list of the 5 most likely tokens.
    The API will always return the `logprob` of the sampled token, so there may be up to
    $logprobs+1 elements in the response.

  The maximum value for $logprobs is 5. If you need more than this, please contact OpenAI
    through their [Help center](https://help.openai.com) and describe your use case.
  */
  logprobs/int?

  /**
  Whether to echo back the prompt in addition to the completion

  Default: false.
  */
  echo/bool?

  /**
  Sequences where the API will stop generating further tokens.

  Up to 4 sequences where the API will stop generating further tokens. The returned
    text will not contain the stop sequence.

  Typical 'stop' sequences include ".", "?", or "\n".
  */
  stop/List?

  /**
  Penalty to apply to new tokens based on whether they appear in the text so far.

  Positive values penalize new tokens based on whether they appear in the text so far,
    increasing the model's likelihood to talk about new topics.

  The value must be between -2.0 and 2.0.
  Default: 0.0.

  See https://platform.openai.com/docs/api-reference/parameter-details more information about frequency and presence penalties.
  */
  presence_penalty/float?

  /**
  Penalty to apply to new tokens based on their existing frequency in the text so far.

  Positive values penalize new tokens based on their existing frequency in the text so far,
    decreasing the model's likelihood to repeat the same line verbatim.

  The value must be between -2.0 and 2.0.
  Default: 0.0.

  See https://platform.openai.com/docs/api-reference/parameter-details more information about frequency and presence penalties.
  */
  frequency_penalty/float?

  /**
  Generates `best_of` completions server-side and returns the "best" (the one with
    the highest log probability per token).

  Results cannot be streamed.

  When used with $n, $best_of controls the number of candidate completions and $n specifies
    how many to return.

  The $best_of value must be greater than $n.

  # Warning

  Because this parameter generates many completions, it can quickly consume your token
    quota. Use carefully and ensure that you have reasonable settings for $max_tokens and $stop.
  */
  best_of/int?

  /**
  Modifies the likelihood of the specified tokens appearing in the completion.

  Accepts a json object that maps tokens (specified by their token ID in the GPT tokenizer)
    to an associated bias value from -100 to 100.

  Mathematically, the bias is added to the logits generated by the model prior to sampling.
    The exact effect varies per model, but values between -1 and 1 should decrease or increase
    likelihood of selection; values like -100 or 100 should result in a ban or exclusive selection
    of the relevant token.

  Use https://platform.openai.com/tokenizer to see how a text is tokenized. That page also provides
    a way to obtain the token ids for a given text.

  # Example
  Use `{"50256": -100}` to prevent the '<|endoftext|>' token from being generated.
  */
  logit_bias/Map?

  /**
  Whether to include the prompt in the response.

  Default: false.
  */
  return_prompt/bool?

  /**
  A unique identifier representing the end-user.

  This can help OpenAI to monitor and detect abuse.
  See https://platform.openai.com/docs/guides/safety-best-practices/end-user-ids.
  */
  user/string?

  constructor
      --.model
      --.prompt=null
      --.max_tokens=null
      --.temperature=null
      --.top_p=null
      --.n=null
      --.stream=null
      --.logprobs=null
      --.echo=null
      --.stop=null
      --.presence_penalty=null
      --.frequency_penalty=null
      --.best_of=null
      --.logit_bias=null
      --.return_prompt=null
      --.user=null:
    if max_tokens and max_tokens < 0: throw "INVALID_ARGUMENT"
    if temperature and not 0.0 <= temperature <= 2.0: throw "INVALID_ARGUMENT"
    if top_p and not 0.0 <= top_p <= 1.0: throw "INVALID_ARGUMENT"
    if n and not 1 <= n <= 128: throw "INVALID_ARGUMENT"
    // We don't test the upper bound for $logprobs, as users can get exceptions.
    if logprobs and not 0 <= logprobs: throw "INVALID_ARGUMENT"
    if presence_penalty and not -2.0 <= presence_penalty <= 2.0: throw "INVALID_ARGUMENT"
    if frequency_penalty and not -2.0 <= frequency_penalty <= 2.0: throw "INVALID_ARGUMENT"

  /**
  Returns a JSON representation of the request.
  */
  to_json -> Map:
    result := {
      "model": model
    }
    if prompt: result["prompt"] = prompt
    if max_tokens: result["max_tokens"] = max_tokens
    if temperature: result["temperature"] = temperature
    if top_p: result["top_p"] = top_p
    if n: result["n"] = n
    // 'stream' is false by default, so we don't need to test for 'null'.
    if stream: result["stream"] = stream
    if logprobs: result["logprobs"] = logprobs
    // 'echo' is false by default, so we don't need to test for 'null'.
    if echo: result["echo"] = echo
    if stop: result["stop"] = stop
    if presence_penalty: result["presence_penalty"] = presence_penalty
    if frequency_penalty: result["frequency_penalty"] = frequency_penalty
    if best_of: result["best_of"] = best_of
    if logit_bias: result["logit_bias"] = logit_bias
    // 'return_prompt' is false by default, so we don't need to test for 'null'.
    if return_prompt: result["return_prompt"] = return_prompt
    if user: result["user"] = user
    return result


class Completion:
  /**
  The ID of the completion.
  */
  id/string

  /**
  The type of the object.
  */
  object/string

  /**
  The time the completion was created.
  */
  created/int

  /**
  The model used to generate the completion.
  */
  model/string

  /**
  The list of choices generated by the model.
  */
  choices/List

  /**
  The usage statistics for the completion.
  */
  usage/Usage?

  constructor.from_json json/Map:
    id = json["id"]
    object = json["object"]
    created = json["created"]
    model = json["model"]
    choices = json["choices"].map: Choice.from_json it
    usage = json.contains "usage" ? Usage.from_json json["usage"]: null

class Choice:
  /**
  The text generated by the model.
  */
  text/string

  /**
  The index of the choice.
  */
  index/int

  /**
  The log probabilities for the tokens in the text.
  */
  logprobs/Logprobs?

  /**
  The reason the model stopped generating text.
  */
  finish_reason/string?

  constructor.from_json json/Map:
    text = json["text"]
    index = json["index"]
    if json.contains "logprobs" and json["logprobs"]:
      logprobs = json["logprobs"].map: Logprobs.from_json it
    else:
      logprobs = null
    finish_reason = json.get "finish_reason"

class Logprobs:
  /**
  The tokens in the text.
  */
  tokens/List

  /**
  The log probabilities for the tokens.
  */
  token_logprobs/List

  /**
  The top log probabilities for the tokens.
  */
  top_logprobs/List

  /**
  The text offset for the tokens.
  */
  text_offset/List

  constructor.from_json json/Map:
    tokens = json["tokens"]
    token_logprobs = json["token_logprobs"]
    top_logprobs = json["top_logprobs"]
    text_offset = json["text_offset"]

class Usage:
  /**
  The number of tokens in the prompt.
  */
  prompt_tokens/int

  /**
  The number of tokens in the completion.
  */
  completion_tokens/int?

  /**
  The total number of tokens in the prompt and completion.
  */
  total_tokens/int

  constructor.from_json json/Map:
    prompt_tokens = json["prompt_tokens"]
    completion_tokens = json.get "completion_tokens"
    total_tokens = json["total_tokens"]

class ChatCompletionRequest:
  /**
  The ID of the model to use for completion.

  Use $Client.models to get a list of available models, or see
    the [Model overview](https://platform.openai.com/docs/models) for a
    description of each model.

  Only `gpt-3.5-turbo` and `gpt-3.5-turbo-0301` are supported.
  */
  model/string

  /**
  The messages to generate chat completions for.

  Each entry must be of type $ChatMessage.

  See https://platform.openai.com/docs/guides/chat/introduction.
  */
  messages/List

  /**
  The maximum number of tokens to generate in the completion.

  The token count of a prompt plus `max_tokens` cannot exceed the model's context length. Most models have a context length of 2048 tokens (except for the newest models, which support 4096).

  Use https://platform.openai.com/tokenizer to see how a text is tokenized. That page also provides
    a way to obtain the token ids for a given text.


  The default value for $max_tokens is equal to 4096 - prompt tokens (the maximum the
    model can generate).
  */
  max_tokens/int?

  /**
  The sampling temperature.

  Higher values, like 0.8 will make the output more random, while lower values, like 0.2 will make
    it more focused and deterministic.

  The temperature must be in the range [0.0, 2.0].
  Default: 1.0.

  We generally recommend altering this or $top_p but not both.

  */
  temperature/float?

  /**
  The probability mass cut-off.

  This is an alternative to sampling with temperature, called nucleus sampling, where the model
    considers the results of the tokens with $top_p probability mass. So 0.1 means only the tokens
    comprising the top 10% probability mass are considered.

  We generally recommend altering this or $temperature but not both.

  The value must be in the range [0.0, 1.0].
  Default: 1.0.
  */
  top_p/float?

  /**
  How many completions to generate for each prompt.

  The value must be in the range [1, 128].
  Default: 1.

  # Warning
  Because this parameter generates many completions, it can quickly consume your token
    quota. Use carefully and ensure that you have reasonable settings for $max_tokens and $stop.
  */
  n/int?

  /**
  Whether to stream back partial progress.

  If set, tokens will be sent as data-only [server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#Event_stream_format)
    as they become available, with the stream terminated by a `data: [DONE]` message.

  Default: false.
  */
  stream/bool?

  /**
  Sequences where the API will stop generating further tokens.

  Up to 4 sequences where the API will stop generating further tokens. The returned
    text will not contain the stop sequence.

  Typical 'stop' sequences include ".", "?", or "\n".
  */
  stop/List?

  /**
  Penalty to apply to new tokens based on whether they appear in the text so far.

  Positive values penalize new tokens based on whether they appear in the text so far,
    increasing the model's likelihood to talk about new topics.

  The value must be between -2.0 and 2.0.
  Default: 0.0.

  See https://platform.openai.com/docs/api-reference/parameter-details more information about frequency and presence penalties.
  */
  presence_penalty/float?

  /**
  Penalty to apply to new tokens based on their existing frequency in the text so far.

  Positive values penalize new tokens based on their existing frequency in the text so far,
    decreasing the model's likelihood to repeat the same line verbatim.

  The value must be between -2.0 and 2.0.
  Default: 0.0.

  See https://platform.openai.com/docs/api-reference/parameter-details more information about frequency and presence penalties.
  */
  frequency_penalty/float?

  /**
  Modifies the likelihood of the specified tokens appearing in the completion.

  Accepts a json object that maps tokens (specified by their token ID in the GPT tokenizer)
    to an associated bias value from -100 to 100.

  Mathematically, the bias is added to the logits generated by the model prior to sampling.
    The exact effect varies per model, but values between -1 and 1 should decrease or increase
    likelihood of selection; values like -100 or 100 should result in a ban or exclusive selection
    of the relevant token.

  Use https://platform.openai.com/tokenizer to see how a text is tokenized. That page also provides
    a way to obtain the token ids for a given text.

  # Example
  Use `{"50256": -100}` to prevent the '<|endoftext|>' token from being generated.
  */
  logit_bias/Map?

  /**
  A unique identifier representing the end-user.

  This can help OpenAI to monitor and detect abuse.
  See https://platform.openai.com/docs/guides/safety-best-practices/end-user-ids.
  */
  user/string?

  constructor
      --.model
      --.messages
      --.max_tokens=null
      --.temperature=null
      --.top_p=null
      --.n=null
      --.stream=null
      --.stop=null
      --.presence_penalty=null
      --.frequency_penalty=null
      --.logit_bias=null
      --.user=null:
    if max_tokens and max_tokens < 0: throw "INVALID_ARGUMENT"
    if temperature and not 0.0 <= temperature <= 2.0: throw "INVALID_ARGUMENT"
    if top_p and not 0.0 <= top_p <= 1.0: throw "INVALID_ARGUMENT"
    if n and not 1 <= n <= 128: throw "INVALID_ARGUMENT"
    if presence_penalty and not -2.0 <= presence_penalty <= 2.0: throw "INVALID_ARGUMENT"
    if frequency_penalty and not -2.0 <= frequency_penalty <= 2.0: throw "INVALID_ARGUMENT"

  to_json -> Map:
    result := {
      "model": model,
      "messages": messages.map: it.to_json,
    }
    if max_tokens: result["max_tokens"] = max_tokens
    if temperature: result["temperature"] = temperature
    if top_p: result["top_p"] = top_p
    if n: result["n"] = n
    if stream: result["stream"] = stream
    if stop: result["stop"] = stop
    if presence_penalty: result["presence_penalty"] = presence_penalty
    if frequency_penalty: result["frequency_penalty"] = frequency_penalty
    if logit_bias: result["logit_bias"] = logit_bias
    if user: result["user"] = user
    return result

/**
A message of the chat conversation.
*/
class ChatMessage:
  static ROLE_SYSTEM ::= "system"
  static ROLE_USER ::= "user"
  static ROLE_ASSISTENT ::= "assistant"

  /**
  The role of the message.

  Must be one of $ROLE_SYSTEM, $ROLE_USER, or $ROLE_ASSISTENT.
  */
  role/string

  /**
  The text of the message.
  */
  content/string

  /**
  The name of the user in a multi-user chat.
  */
  user/string?

  constructor --.role --.content --.user=null:
    if role != ChatMessage.ROLE_SYSTEM and role != ChatMessage.ROLE_USER and role != ChatMessage.ROLE_ASSISTENT:
      throw "INVALID_ARGUMENT"

  constructor.system content/string:
    return ChatMessage --role=ChatMessage.ROLE_SYSTEM --content=content

  constructor.user content/string --user/string?=null:
    return ChatMessage --role=ChatMessage.ROLE_USER --content=content --user=user

  constructor.assistant content/string:
    return ChatMessage --role=ChatMessage.ROLE_ASSISTENT --content=content

  to_json -> Map:
    result := {
      "role": role,
      "content": content,
    }
    if user: result["user"] = user
    return result

  stringify -> string:
    return "$role: $content"

class ChatChoice:
  /** The index of the choice. */
  index/int

  /** The message. */
  message/ChatMessage

  /**
  The reason the message was finished.
  Can be one of
  - 'stop': the API returned a complete model output.
  - 'length': an incomplete output was returned due to the $ChatCompletionRequest.max_tokens limit, or
    due to the model's token limit.
  - 'content_filter': content was omitted due to a flag from OpenAI's content filters.
  - null: the API response is still in progress or incomplete.
  */
  finish_reason/string?

  constructor.from_json json/Map:
    index = json["index"]
    message = ChatMessage --role=json["message"]["role"] --content=json["message"]["content"]
    finish_reason = json. get "finish_reason"


class ChatCompletion:
  /**
  The ID of the completion.
  */
  id/string

  /**
  The type of the object.
  */
  object/string

  /**
  The time the completion was created.
  */
  created/int

  /**
  The model used to generate the completion.
  */
  model/string

  /**
  The list of choices generated by the model.

  Contains a list of $ChatChoice objects.
  */
  choices/List

  /**
  The usage statistics for the completion.
  */
  usage/Usage?

  constructor.from_json json/Map:
    id = json["id"]
    object = json["object"]
    created = json["created"]
    model = json["model"]
    choices = json["choices"].map: ChatChoice.from_json it
    usage = json.contains "usage" ? Usage.from_json json["usage"]: null
