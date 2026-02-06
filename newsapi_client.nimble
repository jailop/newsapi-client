# Package

version       = "0.1.0"
author        = "Jaime Lopez"
description   = "A NewsAPI client, to retrieve market news"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["newsapi"]


# Dependencies

requires "nim >= 2.2.4"

# Tasks

task test, "Run tests":
  exec "nim c -r tests/test_request.nim"

task integration, "Compile integration test (JSON responses)":
  exec "nim c -d:ssl -o:integration/test_pull integration/test_pull.nim"
