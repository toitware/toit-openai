// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import host.os
import openai show *

main args:
  key := os.env.get "OPENAI_KEY"
  if not key:
    print "Please set the OPENAI_KEY environment variable."
    exit 1
  main args --key=key

main args/List --key/string:
  client := Client --key=key

  conversation := [
    ChatMessage.system "You are a helpful assistant.",
    ChatMessage.user "Give me a surprising fact about animals that we frequently encounter.",
  ]
  response := client.complete_chat --conversation=conversation --max_tokens=100
  print "response: $response"
