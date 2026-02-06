import unittest
import ../src/newsapi
import newsapi_client

suite "Argument Parsing Tests":
  
  test "No arguments shows help":
    let args = parseArgs(@[])
    check args.command == ctHelp
  
  test "Help flag":
    check parseArgs(@["--help"]).command == ctHelp
    check parseArgs(@["-h"]).command == ctHelp
    check parseArgs(@["help"]).command == ctHelp
  
  test "Version flag":
    check parseArgs(@["--version"]).command == ctVersion
    check parseArgs(@["-v"]).command == ctVersion
    check parseArgs(@["version"]).command == ctVersion
  
  test "Parse headlines command":
    let args = parseArgs(@["headlines"])
    check args.command == ctHeadlines
    check args.pageSize == 20
    check args.page == 1
    check args.format == ofMarkdown
  
  test "Parse headlines with country":
    let args = parseArgs(@["headlines", "--country=us"])
    check args.command == ctHeadlines
    check args.country == "us"
  
  test "Parse headlines with category":
    let args = parseArgs(@["headlines", "--country=us", "--category=technology"])
    check args.command == ctHeadlines
    check args.country == "us"
    check args.category == ncTechnology
  
  test "Parse headlines with sources":
    let args = parseArgs(@["headlines", "--sources=bbc-news,cnn"])
    check args.command == ctHeadlines
    check args.sources == @["bbc-news", "cnn"]
  
  test "Parse headlines with pagination":
    let args = parseArgs(@["headlines", "--country=us", "--page-size=50", "--page=2"])
    check args.command == ctHeadlines
    check args.pageSize == 50
    check args.page == 2
  
  test "Parse headlines with json format":
    let args = parseArgs(@["headlines", "--country=us", "--json"])
    check args.command == ctHeadlines
    check args.format == ofJson
  
  test "Parse headlines with output file":
    let args = parseArgs(@["headlines", "--country=us", "--output=news.json"])
    check args.command == ctHeadlines
    check args.outputFile == "news.json"
  
  test "Parse sources command":
    let args = parseArgs(@["sources"])
    check args.command == ctSources
    check args.pageSize == 20
  
  test "Parse sources with language and country":
    let args = parseArgs(@["sources", "--language=en", "--country=us"])
    check args.command == ctSources
    check args.language == "en"
    check args.country == "us"
  
  test "Parse everything command with query":
    let args = parseArgs(@["everything", "--query=bitcoin"])
    check args.command == ctEverything
    check args.query == "bitcoin"
    check args.pageSize == 100  # Default for everything
  
  test "Parse everything with all options":
    let args = parseArgs(@[
      "everything",
      "--query=AI",
      "--search-in=title,description",
      "--sources=bbc-news",
      "--domains=bbc.co.uk",
      "--exclude-domains=example.com",
      "--from=2024-01-01",
      "--to=2024-01-31",
      "--language=en",
      "--sort-by=popularity",
      "--page-size=50",
      "--page=2"
    ])
    check args.command == ctEverything
    check args.query == "AI"
    check args.searchIn == @[sicTitle, sicDescription]
    check args.sources == @["bbc-news"]
    check args.domains == @["bbc.co.uk"]
    check args.excludeDomains == @["example.com"]
    check args.fromDate == "2024-01-01"
    check args.toDate == "2024-01-31"
    check args.language == "en"
    check args.sortBy == sbPopularity
    check args.pageSize == 50
    check args.page == 2
  
  test "Parse with pretty json format":
    let args = parseArgs(@["headlines", "--country=us", "--pretty"])
    check args.command == ctHeadlines
    check args.format == ofJsonPretty
  
  test "Command abbreviation - headlines":
    let word = "headlines"
    for i in 1..word.len:
      let abbrev = word[0..<i]
      check parseArgs(@[abbrev]).command == ctHeadlines
  
  test "Command abbreviation - sources":
    let word = "sources"
    for i in 1..word.len:
      let abbrev = word[0..<i]
      check parseArgs(@[abbrev]).command == ctSources
  
  test "Command abbreviation - everything":
    let word = "everything"
    for i in 1..word.len:
      let abbrev = word[0..<i]
      check parseArgs(@[abbrev]).command == ctEverything
  
  test "Abbreviation with options":
    let args = parseArgs(@["hea", "--country=us"])
    check args.command == ctHeadlines
    check args.country == "us"
    
    let args2 = parseArgs(@["sou", "--language=en"])
    check args2.command == ctSources
    check args2.language == "en"
    
    let args3 = parseArgs(@["ev", "--query=test"])
    check args3.command == ctEverything
    check args3.query == "test"
  
  test "Case insensitive abbreviations":
    check parseArgs(@["HEA"]).command == ctHeadlines
    check parseArgs(@["SOU"]).command == ctSources
    check parseArgs(@["EVE"]).command == ctEverything
    check parseArgs(@["HeAdLiNeS"]).command == ctHeadlines

