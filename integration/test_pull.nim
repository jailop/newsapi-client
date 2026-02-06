import std/[asyncdispatch, os, times]
import ../src/newsapi_client

proc getApiKey(): string =
  result = getEnv("NEWSAPI_KEY")
  if result == "":
    stderr.writeLine("Error: NEWSAPI_KEY environment variable not set")
    quit(1)

proc testHeadlinesPull() {.async.} =
  echo "\n=== Testing Headlines with pull() ==="
  let apiKey = getApiKey()
  
  let req = HeadLinesRequest(
    apiKey: apiKey,
    country: "us",
    category: ncTechnology,
    pageSize: 5,
    page: 1
  )
  
  try:
    let response = await pull(req)
    echo "Status: ", response.status
    echo "Total results: ", response.totalResults
    echo "Articles count: ", response.articles.len
    
    if response.articles.len > 0:
      echo "\nFirst article:"
      echo "  Title: ", response.articles[0].title
      echo "  Source: ", response.articles[0].source.name
      echo "  Author: ", response.articles[0].author
  except Exception as e:
    echo "Error: ", e.msg

proc testSourcesPull() {.async.} =
  echo "\n=== Testing Sources with pull() ==="
  let apiKey = getApiKey()
  
  let req = SourcesRequest(
    apiKey: apiKey,
    category: ncTechnology,
    language: "en",
    country: "us"
  )
  
  try:
    let response = await pull(req)
    echo "Status: ", response.status
    echo "Sources count: ", response.sources.len
    
    if response.sources.len > 0:
      echo "\nFirst source:"
      echo "  Name: ", response.sources[0].name
      echo "  ID: ", response.sources[0].id
      echo "  Description: ", response.sources[0].description
  except Exception as e:
    echo "Error: ", e.msg

proc testEverythingPull() {.async.} =
  echo "\n=== Testing Everything with pull() ==="
  let apiKey = getApiKey()
  
  let now = getTime()
  let weekAgo = now - 7.days
  
  let req = EverythingRequest(
    apiKey: apiKey,
    q: "artificial intelligence",
    searchIn: @[sicTitle],
    language: "en",
    sortBy: sbPublishedAt,
    `from`: weekAgo.format("yyyy-MM-dd"),
    `to`: now.format("yyyy-MM-dd"),
    pageSize: 5,
    page: 1
  )
  
  try:
    let response = await pull(req)
    echo "Status: ", response.status
    echo "Total results: ", response.totalResults
    echo "Articles count: ", response.articles.len
    
    if response.articles.len > 0:
      echo "\nFirst article:"
      echo "  Title: ", response.articles[0].title
      echo "  URL: ", response.articles[0].url
      echo "  Published: ", response.articles[0].publishedAt
  except Exception as e:
    echo "Error: ", e.msg

proc testErrorHandling() {.async.} =
  echo "\n=== Testing Error Handling ==="
  
  let req = HeadLinesRequest(
    apiKey: "invalid-key",
    country: "us",
    category: ncGeneral,
    pageSize: 5,
    page: 1
  )
  
  try:
    discard await pull(req)
    echo "Unexpected success with invalid key"
  except Exception as e:
    echo "Correctly caught error: ", e.msg

proc main() {.async.} =
  echo "NewsAPI Client Integration Tests"
  
  await testHeadlinesPull()
  await testSourcesPull()
  await testEverythingPull()
  await testErrorHandling()
  
  echo "\n=== Tests completed ==="

when isMainModule:
  waitFor main()
