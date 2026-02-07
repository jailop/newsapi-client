import std/[asyncdispatch, os, json, strutils, parseopt]
import newsapi_client

const version = "0.1.0"

type
  CommandType* = enum
    ctNone,
    ctHeadlines,
    ctSources,
    ctEverything,
    ctHelp,
    ctVersion

  Args* = object
    command*: CommandType
    # Headlines options
    country*: string
    category*: NewsCategory
    sources*: seq[string]
    # Sources options (country and category reused)
    language*: string
    # Everything options
    query*: string
    searchIn*: seq[SearchInCategory]
    domains*: seq[string]
    excludeDomains*: seq[string]
    fromDate*: string
    toDate*: string
    sortBy*: SortByCategory
    # Common options
    pageSize*: int
    page*: int
    format*: OutputFormat
    outputFile*: string

  OutputFormat* = enum
    ofMarkdown,
    ofJson,
    ofJsonPretty

proc showHelp() =
  echo """
NewsAPI Command Line Client

Usage:
  newsapi headlines [options]      Get top headlines
  newsapi sources [options]        Get news sources
  newsapi everything [options]     Search everything
  newsapi --help                   Show this help
  newsapi --version                Show version information

Environment:
  NEWSAPI_KEY                      Your NewsAPI key (required)

Options for 'headlines':
  --country=CODE                   Country code (e.g., us, gb, de)
  --category=CAT                   Category (business, entertainment, general, 
                                   health, science, sports, technology)
  --sources=LIST                   Comma-separated source IDs
  --page-size=N                    Number of results (default: 20, max: 100)
  --page=N                         Page number (default: 1)

Options for 'sources':
  --country=CODE                   Country code
  --category=CAT                   Category filter
  --language=CODE                  Language code (e.g., en, es, fr)

Options for 'everything':
  --query=TEXT                     Search query (required)
  --search-in=LIST                 Comma-separated: title,description,content
  --sources=LIST                   Comma-separated source IDs
  --domains=LIST                   Comma-separated domains
  --exclude-domains=LIST           Comma-separated domains to exclude
  --from=DATE                      Start date (YYYY-MM-DD or ISO 8601 datetime)
  --to=DATE                        End date (YYYY-MM-DD or ISO 8601 datetime)
  --language=CODE                  Language code
  --sort-by=SORT                   Sort by: relevancy, popularity, publishedAt
  --page-size=N                    Number of results (default: 100, max: 100)
  --page=N                         Page number (default: 1)

Common options:
  --markdown                       Output as Markdown (default)
  --json                           Output raw JSON
  --pretty                         Pretty print JSON
  --output=FILE                    Write output to file

Examples:
  newsapi headlines --country=us --category=technology
  newsapi sources --language=en --category=business
  newsapi everything --query="AI" --from=2024-01-01 --to=2024-01-31
  newsapi headlines --country=us --json --output=news.json

For more information, visit https://newsapi.org/docs
This software is not affiliated with NewsAPI.org
"""
  quit(0)

proc getApiKey(): string =
  result = getEnv("NEWSAPI_KEY")
  if result == "":
    stderr.writeLine("Error: NEWSAPI_KEY environment variable not set")
    stderr.writeLine("Set it with: export NEWSAPI_KEY=your_api_key")
    quit(1)

## Enables command abbreviation: any unambiguous prefix matches the full
## command name (h for headlines, s for sources, e for everything).
proc matchCommand(input: string): CommandType =
  let cmd = input.toLowerAscii()
  
  if cmd in ["--help", "-h", "help"]:
    return ctHelp
  if cmd in ["--version", "-v", "version"]:
    return ctVersion
  
  if "headlines".startsWith(cmd):
    return ctHeadlines
  elif "sources".startsWith(cmd):
    return ctSources
  elif "everything".startsWith(cmd):
    return ctEverything
  else:
    return ctNone

proc parseArgs*(cmdLineParams: seq[string] = commandLineParams()): Args =
  result = Args(
    command: ctNone,
    category: ncGeneral,
    sortBy: sbPublishedAt,
    pageSize: 20,
    page: 1,
    format: ofMarkdown
  )
  
  if cmdLineParams.len == 0:
    result.command = ctHelp
    return
  
  let cmd = cmdLineParams[0]
  result.command = matchCommand(cmd)
  
  if result.command == ctNone:
    stderr.writeLine("Error: Unknown command: " & cmd)
    stderr.writeLine("Use 'newsapi --help' for usage information")
    quit(1)
  
  if result.command in [ctHelp, ctVersion]:
    return
  
  if result.command == ctEverything:
    result.pageSize = 100
  
  if cmdLineParams.len == 1:
    return
  
  var p = initOptParser(cmdLineParams[1..^1])
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key.toLowerAscii()
      of "country": result.country = p.val
      of "category":
        try:
          result.category = parseCategory(p.val)
        except ValueError as e:
          stderr.writeLine("Error: " & e.msg)
          quit(1)
      of "sources": result.sources = p.val.split(',')
      of "language": result.language = p.val
      of "query", "q": result.query = p.val
      of "search-in", "searchin":
        for item in p.val.split(','):
          try:
            result.searchIn.add(parseSearchIn(item))
          except ValueError as e:
            stderr.writeLine("Error: " & e.msg)
            quit(1)
      of "domains": result.domains = p.val.split(',')
      of "exclude-domains", "excludedomains": result.excludeDomains = p.val.split(',')
      of "from": result.fromDate = p.val
      of "to": result.toDate = p.val
      of "sort-by", "sortby":
        try:
          result.sortBy = parseSortBy(p.val)
        except ValueError as e:
          stderr.writeLine("Error: " & e.msg)
          quit(1)
      of "page-size", "pagesize": result.pageSize = parseInt(p.val)
      of "page": result.page = parseInt(p.val)
      of "markdown": result.format = ofMarkdown
      of "json": result.format = ofJson
      of "pretty": result.format = ofJsonPretty
      of "output": result.outputFile = p.val
      else:
        stderr.writeLine("Unknown option: --" & p.key)
        quit(1)
    of cmdArgument:
      stderr.writeLine("Unexpected argument: " & p.key)
      quit(1)

proc articlesToMarkdown(articles: seq[NewsArticle]): string =
  result = ""
  for article in articles:
    result.add("## " & article.title & "\n\n")
    result.add("**Source:** " & article.source.name & "  \n")
    result.add("**Author:** " & article.author & "  \n")
    result.add("**Published:** " & article.publishedAt & "  \n")
    if article.description.len > 0:
      result.add("\n" & article.description & "\n\n")
    if article.url.len > 0:
      result.add("[Read more](" & article.url & ")\n\n")
    if article.urlToImage.len > 0:
      result.add("![Image](" & article.urlToImage & ")\n\n")
    result.add("---\n\n")

proc articlesToMarkdown(articles: JsonNode): string =
  result = ""
  for i, article in articles:
    let source = article{"source"}{"name"}.getStr("Unknown")
    let author = article{"author"}.getStr("Unknown")
    let title = article{"title"}.getStr("No title")
    let description = article{"description"}.getStr("")
    let url = article{"url"}.getStr("")
    let publishedAt = article{"publishedAt"}.getStr("")
    let urlToImage = article{"urlToImage"}.getStr("")
    
    result.add("## " & title & "\n\n")
    result.add("**Source:** " & source & "  \n")
    result.add("**Author:** " & author & "  \n")
    result.add("**Published:** " & publishedAt & "  \n")
    if description.len > 0:
      result.add("\n" & description & "\n\n")
    if url.len > 0:
      result.add("[Read more](" & url & ")\n\n")
    if urlToImage.len > 0:
      result.add("![Image](" & urlToImage & ")\n\n")
    result.add("---\n\n")

proc sourcesToMarkdown(sources: seq[NewsSource]): string =
  result = "# News Sources\n\n"
  for source in sources:
    result.add("## " & source.name & "\n\n")
    if source.id.len > 0:
      result.add("**ID:** `" & source.id & "`  \n")
    result.add("**Category:** " & $source.category & "  \n")
    if source.language.len > 0:
      result.add("**Language:** " & source.language & "  \n")
    if source.country.len > 0:
      result.add("**Country:** " & source.country & "  \n")
    if source.description.len > 0:
      result.add("\n" & source.description & "\n\n")
    if source.url.len > 0:
      result.add("[Visit source](" & source.url & ")\n\n")
    result.add("---\n\n")

proc sourcesToMarkdown(sources: JsonNode): string =
  result = "# News Sources\n\n"
  for source in sources:
    let id = source{"id"}.getStr("")
    let name = source{"name"}.getStr("Unknown")
    let description = source{"description"}.getStr("")
    let url = source{"url"}.getStr("")
    let category = source{"category"}.getStr("")
    let language = source{"language"}.getStr("")
    let country = source{"country"}.getStr("")
    
    result.add("## " & name & "\n\n")
    if id.len > 0:
      result.add("**ID:** `" & id & "`  \n")
    if category.len > 0:
      result.add("**Category:** " & category & "  \n")
    if language.len > 0:
      result.add("**Language:** " & language & "  \n")
    if country.len > 0:
      result.add("**Country:** " & country & "  \n")
    if description.len > 0:
      result.add("\n" & description & "\n\n")
    if url.len > 0:
      result.add("[Visit source](" & url & ")\n\n")
    result.add("---\n\n")

proc outputResult(response: NewsResponse, format: OutputFormat, outputFile: string) =
  var output = ""
  
  case format
  of ofMarkdown:
    output = "# News Articles\n\n"
    output.add("**Total Results:** " & $response.totalResults & "\n\n")
    output.add("---\n\n")
    output.add(articlesToMarkdown(response.articles))
  of ofJson:
    output = $(%response)
  of ofJsonPretty:
    output = pretty(%response)
  
  if outputFile.len > 0:
    writeFile(outputFile, output)
    echo "Output written to: ", outputFile
  else:
    echo output

proc outputResult(response: SourcesResponse, format: OutputFormat, outputFile: string) =
  var output = ""
  
  case format
  of ofMarkdown:
    output = sourcesToMarkdown(response.sources)
  of ofJson:
    output = $(%response)
  of ofJsonPretty:
    output = pretty(%response)
  
  if outputFile.len > 0:
    writeFile(outputFile, output)
    echo "Output written to: ", outputFile
  else:
    echo output

proc outputResult(jsonData: string, format: OutputFormat, outputFile: string) =
  var output = ""
  
  case format
  of ofMarkdown:
    try:
      let parsed = parseJson(jsonData)
      let status = parsed{"status"}.getStr()
      
      if status == "error":
        let code = parsed{"code"}.getStr("unknown")
        let message = parsed{"message"}.getStr("An error occurred")
        output = "# Error\n\n**Code:** " & code & "  \n**Message:** " & message & "\n"
      else:
        if parsed.hasKey("articles"):
          let totalResults = parsed{"totalResults"}.getInt(0)
          output = "# News Articles\n\n"
          output.add("**Total Results:** " & $totalResults & "\n\n")
          output.add("---\n\n")
          output.add(articlesToMarkdown(parsed["articles"]))
        elif parsed.hasKey("sources"):
          output = sourcesToMarkdown(parsed["sources"])
        else:
          output = jsonData
    except:
      output = jsonData
  of ofJson:
    output = jsonData
  of ofJsonPretty:
    try:
      let parsed = parseJson(jsonData)
      output = parsed.pretty()
    except:
      output = jsonData
  
  if outputFile != "":
    writeFile(outputFile, output)
    echo "Output written to: ", outputFile
  else:
    echo output

proc executeHeadlines(args: Args) {.async.} =
  if args.country == "" and args.sources.len == 0:
    stderr.writeLine("Error: headlines command requires either --country or --sources")
    stderr.writeLine("Use 'newsapi --help' for usage information")
    quit(1)
  
  let req = HeadLinesRequest(
    apiKey: getApiKey(),
    country: args.country,
    category: args.category,
    sources: args.sources,
    pageSize: args.pageSize,
    page: args.page
  )
  
  let response = await pull(req)
  outputResult(response, args.format, args.outputFile)

proc executeSources(args: Args) {.async.} =
  let req = SourcesRequest(
    apiKey: getApiKey(),
    category: args.category,
    language: args.language,
    country: args.country
  )
  
  let response = await pull(req)
  outputResult(response, args.format, args.outputFile)

proc executeEverything(args: Args) {.async.} =
  if args.query == "":
    stderr.writeLine("Error: --query is required for 'everything' command")
    quit(1)
  
  let req = EverythingRequest(
    apiKey: getApiKey(),
    q: args.query,
    searchIn: args.searchIn,
    sources: args.sources,
    domains: args.domains,
    excludeDomains: args.excludeDomains,
    `from`: args.fromDate,
    `to`: args.toDate,
    language: args.language,
    sortBy: args.sortBy,
    pageSize: args.pageSize,
    page: args.page
  )
  
  let response = await pull(req)
  outputResult(response, args.format, args.outputFile)

proc showVersion() =
  echo "NewsAPI CLI version ", version
  quit(0)

proc main() {.async.} =
  let args = parseArgs()
  
  case args.command
  of ctHelp:
    showHelp()
  of ctVersion:
    showVersion()
  of ctHeadlines:
    await executeHeadlines(args)
  of ctSources:
    await executeSources(args)
  of ctEverything:
    await executeEverything(args)
  of ctNone:
    stderr.writeLine("Error: No command specified")
    stderr.writeLine("Use 'newsapi --help' for usage information")
    quit(1)

when isMainModule:
  try:
    waitFor main()
  except Exception as e:
    stderr.writeLine("Error: " & e.msg)
    quit(1)
