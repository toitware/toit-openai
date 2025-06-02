// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import certificate-roots
import encoding.json
import http
import net

OPENAI-HOST ::= "api.openai.com"
DEFAULT-COMPLETION-MODEL ::= "davinci"
DEFAULT-CHAT-MODEL ::= "gpt-3.5-turbo"
DEFAULT-COMPLETION-MAX-TOKENS ::= 50
DEFAULT-CHAT-MAX-TOKENS ::= 50

/**
A client for the OpenAI API.
*/
class Client:
  key_/string
  network_/net.Interface? := ?
  client_/http.Client? := ?
  models_/Models? := null
  headers_/http.Headers? := null
  completion-model_/string
  completion-max-tokens_/int
  chat-model_/string
  chat-max-tokens_/int

  /**
  Constructs a new client with the given $key.

  The $completion-model is the default model to use for completions. It
    can also be changed by specifying the 'model' parameter in the
    $complete method. It defaults to $DEFAULT-COMPLETION-MODEL.

  The $completion-max-tokens is the default number of tokens to generate
    for completions. It can also be changed by specifying the 'max_tokens'
    parameter in the $complete method. It defaults to
    $DEFAULT-COMPLETION-MAX-TOKENS.

  The $chat-model is the default model to use for chat completions. It
    can also be changed by specifying the 'model' parameter in the
    $complete-chat method. It defaults to $DEFAULT-CHAT-MODEL.

  The $chat-max-tokens is the default number of tokens to generate
    for chat completions. It can also be changed by specifying the 'max_tokens'
    parameter in the $complete-chat method. It defaults to
    $DEFAULT-CHAT-MAX-TOKENS.

  If $install-common-trusted-roots is set (the default), installs all common
    trusted roots. If this flag is set to false, install the roots manually
    before using the client.

  Keys are managed here: https://platform.openai.com/account/api-keys.
  */
  constructor --key/string
      --completion-model/string=DEFAULT-COMPLETION-MODEL
      --completion-max-tokens/int=DEFAULT-COMPLETION-MAX-TOKENS
      --chat-model/string=DEFAULT-CHAT-MODEL
      --chat-max-tokens/int=DEFAULT-CHAT-MAX-TOKENS
      --install-common-trusted-roots/bool=true:
    if install-common-trusted-roots:
      certificate-roots.install-common-trusted-roots
    key_ = key
    completion-model_ = completion-model
    completion-max-tokens_ = completion-max-tokens
    chat-model_ = chat-model
    chat-max-tokens_ = chat-max-tokens
    network_ = net.open
    client_ = http.Client.tls network_

  close:
    if client_:
      client_.close
      client_ = null
    if network_:
      network_.close
      network_ = null

  /**
  Completes the given $prompt with the given $model.

  The $model defaults to the one specified at construction of this instance.

  Use $max-tokens to limit the number of tokens generated. It defaults to
    the one specified at construction of this instance.

  Use $stop to specify a list of tokens that will stop the completion.

  Returns the generated text.

  This is a shorthand version of $(complete request).

  Deprecated. OpenAI has deprecated this endpoint.

  # Examples
  ```
  client := Client --key=OPENAI_KEY
  text := client.complete --prompt="The quick brown fox jumps over the lazy "
  print text
  ```
  */
  complete -> string
      --prompt/string
      --model=completion-model_
      --max-tokens=completion-max-tokens_
      --stop/List?=null:
    request := CompletionRequest
        --model=model
        --prompt=prompt
        --max-tokens=max-tokens
        --stop=stop
    completion := complete request
    choice := completion.choices[0]
    return choice.text

  /**
  Requests a completion for the given $request.
  */
  complete request/CompletionRequest -> Completion:
    response := post_ "/v1/completions" request.to-json
    return Completion.from-json response

  /**
  Completes the given $conversation with the given $model.

  The $model defaults to the one specified at construction of this instance.

  Use $max-tokens to limit the number of tokens generated. It defaults to
    the one specified at construction of this instance.

  Use $stop to specify a list of tokens that will stop the completion.

  Returns the generated text.

  This is a shorthand version of $(complete-chat request).

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
  complete-chat -> string
      --conversation/List
      --model=chat-model_
      --max-tokens=chat-max-tokens_
      --stop/List?=null:
    request := ChatCompletionRequest
        --model=model
        --messages=conversation
        --max-tokens=max-tokens
        --stop=stop
    completion := complete-chat request
    choice/ChatChoice := completion.choices[0]
    return choice.message.content

  /**
  Requests a completion for the given $request.
  */
  complete-chat request/ChatCompletionRequest -> ChatCompletion:
    response := post_ "/v1/chat/completions" request.to-json
    return ChatCompletion.from-json response

  /**
  Returns the $Models object, allowing access to model-related functionality.
  */
  models -> Models:
    if not models_: models_ = Models this
    return models_

  authorization-headers_ -> http.Headers:
    // TODO(florian): switch to saved header once the http library
    // doesn't modify the header anymore.
    // if not headers_:
    //   headers_ = http.Headers
    //   headers_.add "Authorization" "Bearer $key_"
    headers_ = http.Headers
    headers_.add "Authorization" "Bearer $key_"
    return headers_

  post_ path/string payload/Map  -> Map:
    response := client_.post-json payload
        --headers=authorization-headers_
        --host=OPENAI-HOST
        --path=path
    return decode-response_ response

  get_ path/string -> Map:
    response := client_.get
        --headers=authorization-headers_
        --host=OPENAI-HOST
        --path=path
    return decode-response_ response

  decode-response_ response/http.Response -> Map:
    try:
      if response.status-code != 200:
        decoded-object := null
        catch:
          decoded-object = json.decode-stream response.body
        error-object := decoded-object and decoded-object.get "error"
        if not error-object: error-object = {:}
        exception := OpenAIException
            --status-code=response.status-code
            --status-message=response.status-message
            --message=error-object.get "message"
            --type=error-object.get "type"
            --param=error-object.get "param"
            --code=error-object.get "code"
        throw exception
      response-payload := json.decode-stream response.body
      return response-payload
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
  owned-by/string
  permission/List?

  constructor.from-json json/Map:
    id = json["id"]
    object = json["object"]
    created = json["created"]
    owned-by = json["owned_by"]
    permission = json.get "permission"

  stringify -> string:
    return "Model: $id (owned_by $owned-by)"

class Models:
  client_/Client

  constructor .client_:

  list -> List:
    response := client_.get_ "/v1/models"
    return response["data"].map: Model.from-json it

  operator [] id/string -> Model:
    response := client_.get_ "/v1/models/$id"
    return Model.from-json response

class OpenAIException:
  status-code/int
  status-message/string
  message/string?
  type/string?
  param/any
  code/any

  constructor
      --.status-code
      --.status-message
      --.message
      --.type
      --.param
      --.code:

  stringify -> string:
    return "OpenAIException: $status-code - $status-message - $message ($type)"

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
  max-tokens/int?

  /**
  The sampling temperature.

  Higher values, like 0.8 will make the output more random, while lower values, like 0.2 will make
    it more focused and deterministic.

  The temperature must be in the range [0.0, 2.0].
  Default: 1.0.

  We generally recommend altering this or $top-p but not both.

  */
  temperature/float?

  /**
  The probability mass cut-off.

  This is an alternative to sampling with temperature, called nucleus sampling, where the model
    considers the results of the tokens with $top-p probability mass. So 0.1 means only the tokens
    comprising the top 10% probability mass are considered.

  We generally recommend altering this or $temperature but not both.

  The value must be in the range [0.0, 1.0].
  Default: 1.0.
  */
  top-p/float?

  /**
  How many completions to generate for each prompt.

  The value must be in the range [1, 128].
  Default: 1.

  # Warning
  Because this parameter generates many completions, it can quickly consume your token
    quota. Use carefully and ensure that you have reasonable settings for $max-tokens and $stop.
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
  presence-penalty/float?

  /**
  Penalty to apply to new tokens based on their existing frequency in the text so far.

  Positive values penalize new tokens based on their existing frequency in the text so far,
    decreasing the model's likelihood to repeat the same line verbatim.

  The value must be between -2.0 and 2.0.
  Default: 0.0.

  See https://platform.openai.com/docs/api-reference/parameter-details more information about frequency and presence penalties.
  */
  frequency-penalty/float?

  /**
  Generates `best_of` completions server-side and returns the "best" (the one with
    the highest log probability per token).

  Results cannot be streamed.

  When used with $n, $best-of controls the number of candidate completions and $n specifies
    how many to return.

  The $best-of value must be greater than $n.

  # Warning

  Because this parameter generates many completions, it can quickly consume your token
    quota. Use carefully and ensure that you have reasonable settings for $max-tokens and $stop.
  */
  best-of/int?

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
  logit-bias/Map?

  /**
  Whether to include the prompt in the response.

  Default: false.
  */
  return-prompt/bool?

  /**
  A unique identifier representing the end-user.

  This can help OpenAI to monitor and detect abuse.
  See https://platform.openai.com/docs/guides/safety-best-practices/end-user-ids.
  */
  user/string?

  constructor
      --.model
      --.prompt=null
      --.max-tokens=null
      --.temperature=null
      --.top-p=null
      --.n=null
      --.stream=null
      --.logprobs=null
      --.echo=null
      --.stop=null
      --.presence-penalty=null
      --.frequency-penalty=null
      --.best-of=null
      --.logit-bias=null
      --.return-prompt=null
      --.user=null:
    if max-tokens and max-tokens < 0: throw "INVALID_ARGUMENT"
    if temperature and not 0.0 <= temperature <= 2.0: throw "INVALID_ARGUMENT"
    if top-p and not 0.0 <= top-p <= 1.0: throw "INVALID_ARGUMENT"
    if n and not 1 <= n <= 128: throw "INVALID_ARGUMENT"
    // We don't test the upper bound for $logprobs, as users can get exceptions.
    if logprobs and not 0 <= logprobs: throw "INVALID_ARGUMENT"
    if presence-penalty and not -2.0 <= presence-penalty <= 2.0: throw "INVALID_ARGUMENT"
    if frequency-penalty and not -2.0 <= frequency-penalty <= 2.0: throw "INVALID_ARGUMENT"

  /**
  Returns a JSON representation of the request.
  */
  to-json -> Map:
    result := {
      "model": model
    }
    if prompt: result["prompt"] = prompt
    if max-tokens: result["max_tokens"] = max-tokens
    if temperature: result["temperature"] = temperature
    if top-p: result["top_p"] = top-p
    if n: result["n"] = n
    // 'stream' is false by default, so we don't need to test for 'null'.
    if stream: result["stream"] = stream
    if logprobs: result["logprobs"] = logprobs
    // 'echo' is false by default, so we don't need to test for 'null'.
    if echo: result["echo"] = echo
    if stop: result["stop"] = stop
    if presence-penalty: result["presence_penalty"] = presence-penalty
    if frequency-penalty: result["frequency_penalty"] = frequency-penalty
    if best-of: result["best_of"] = best-of
    if logit-bias: result["logit_bias"] = logit-bias
    // 'return_prompt' is false by default, so we don't need to test for 'null'.
    if return-prompt: result["return_prompt"] = return-prompt
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

  constructor.from-json json/Map:
    id = json["id"]
    object = json["object"]
    created = json["created"]
    model = json["model"]
    choices = json["choices"].map: Choice.from-json it
    usage = json.contains "usage" ? Usage.from-json json["usage"]: null

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
  finish-reason/string?

  constructor.from-json json/Map:
    text = json["text"]
    index = json["index"]
    if json.contains "logprobs" and json["logprobs"]:
      logprobs = json["logprobs"].map: Logprobs.from-json it
    else:
      logprobs = null
    finish-reason = json.get "finish_reason"

class Logprobs:
  /**
  The tokens in the text.
  */
  tokens/List

  /**
  The log probabilities for the tokens.
  */
  token-logprobs/List

  /**
  The top log probabilities for the tokens.
  */
  top-logprobs/List

  /**
  The text offset for the tokens.
  */
  text-offset/List

  constructor.from-json json/Map:
    tokens = json["tokens"]
    token-logprobs = json["token_logprobs"]
    top-logprobs = json["top_logprobs"]
    text-offset = json["text_offset"]

class Usage:
  /**
  The number of tokens in the prompt.
  */
  prompt-tokens/int

  /**
  The number of tokens in the completion.
  */
  completion-tokens/int?

  /**
  The total number of tokens in the prompt and completion.
  */
  total-tokens/int

  constructor.from-json json/Map:
    prompt-tokens = json["prompt_tokens"]
    completion-tokens = json.get "completion_tokens"
    total-tokens = json["total_tokens"]

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


  The default value for $max-tokens is equal to 4096 - prompt tokens (the maximum the
    model can generate).
  */
  max-tokens/int?

  /**
  The sampling temperature.

  Higher values, like 0.8 will make the output more random, while lower values, like 0.2 will make
    it more focused and deterministic.

  The temperature must be in the range [0.0, 2.0].
  Default: 1.0.

  We generally recommend altering this or $top-p but not both.

  */
  temperature/float?

  /**
  The probability mass cut-off.

  This is an alternative to sampling with temperature, called nucleus sampling, where the model
    considers the results of the tokens with $top-p probability mass. So 0.1 means only the tokens
    comprising the top 10% probability mass are considered.

  We generally recommend altering this or $temperature but not both.

  The value must be in the range [0.0, 1.0].
  Default: 1.0.
  */
  top-p/float?

  /**
  How many completions to generate for each prompt.

  The value must be in the range [1, 128].
  Default: 1.

  # Warning
  Because this parameter generates many completions, it can quickly consume your token
    quota. Use carefully and ensure that you have reasonable settings for $max-tokens and $stop.
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
  presence-penalty/float?

  /**
  Penalty to apply to new tokens based on their existing frequency in the text so far.

  Positive values penalize new tokens based on their existing frequency in the text so far,
    decreasing the model's likelihood to repeat the same line verbatim.

  The value must be between -2.0 and 2.0.
  Default: 0.0.

  See https://platform.openai.com/docs/api-reference/parameter-details more information about frequency and presence penalties.
  */
  frequency-penalty/float?

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
  logit-bias/Map?

  /**
  A unique identifier representing the end-user.

  This can help OpenAI to monitor and detect abuse.
  See https://platform.openai.com/docs/guides/safety-best-practices/end-user-ids.
  */
  user/string?

  constructor
      --.model
      --.messages
      --.max-tokens=null
      --.temperature=null
      --.top-p=null
      --.n=null
      --.stream=null
      --.stop=null
      --.presence-penalty=null
      --.frequency-penalty=null
      --.logit-bias=null
      --.user=null:
    if max-tokens and max-tokens < 0: throw "INVALID_ARGUMENT"
    if temperature and not 0.0 <= temperature <= 2.0: throw "INVALID_ARGUMENT"
    if top-p and not 0.0 <= top-p <= 1.0: throw "INVALID_ARGUMENT"
    if n and not 1 <= n <= 128: throw "INVALID_ARGUMENT"
    if presence-penalty and not -2.0 <= presence-penalty <= 2.0: throw "INVALID_ARGUMENT"
    if frequency-penalty and not -2.0 <= frequency-penalty <= 2.0: throw "INVALID_ARGUMENT"

  to-json -> Map:
    result := {
      "model": model,
      "messages": messages.map: it.to-json,
    }
    if max-tokens: result["max_tokens"] = max-tokens
    if temperature: result["temperature"] = temperature
    if top-p: result["top_p"] = top-p
    if n: result["n"] = n
    if stream: result["stream"] = stream
    if stop: result["stop"] = stop
    if presence-penalty: result["presence_penalty"] = presence-penalty
    if frequency-penalty: result["frequency_penalty"] = frequency-penalty
    if logit-bias: result["logit_bias"] = logit-bias
    if user: result["user"] = user
    return result

/**
A message of the chat conversation.
*/
class ChatMessage:
  static ROLE-SYSTEM ::= "system"
  static ROLE-USER ::= "user"
  static ROLE-ASSISTENT ::= "assistant"

  /**
  The role of the message.

  Must be one of $ROLE-SYSTEM, $ROLE-USER, or $ROLE-ASSISTENT.
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
    if role != ChatMessage.ROLE-SYSTEM and role != ChatMessage.ROLE-USER and role != ChatMessage.ROLE-ASSISTENT:
      throw "INVALID_ARGUMENT"

  constructor.system content/string:
    return ChatMessage --role=ChatMessage.ROLE-SYSTEM --content=content

  constructor.user content/string --user/string?=null:
    return ChatMessage --role=ChatMessage.ROLE-USER --content=content --user=user

  constructor.assistant content/string:
    return ChatMessage --role=ChatMessage.ROLE-ASSISTENT --content=content

  to-json -> Map:
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
  - 'length': an incomplete output was returned due to the $ChatCompletionRequest.max-tokens limit, or
    due to the model's token limit.
  - 'content_filter': content was omitted due to a flag from OpenAI's content filters.
  - null: the API response is still in progress or incomplete.
  */
  finish-reason/string?

  constructor.from-json json/Map:
    index = json["index"]
    message = ChatMessage --role=json["message"]["role"] --content=json["message"]["content"]
    finish-reason = json. get "finish_reason"


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

  constructor.from-json json/Map:
    id = json["id"]
    object = json["object"]
    created = json["created"]
    model = json["model"]
    choices = json["choices"].map: ChatChoice.from-json it
    usage = json.contains "usage" ? Usage.from-json json["usage"]: null
