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
  prompt := "This is a test"
  if args.size > 0: prompt = args[0]

  client := Client --key=key

  response := client.complete --prompt=prompt --stop=["."]
  print "response: $response"
