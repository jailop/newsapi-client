import std/[asyncdispatch, os, json, strutils, parseopt]
import newsapi_client

const version = "0.1.0"

type
  ## CommandType enumerates the available command-line commands recognized
  ## by the newsapi utility. Values correspond to the three primary NewsAPI
  ## endpoints (headlines, sources, everything) plus help and version
  ## requests. The ctNone value indicates an unrecognized or missing
  ## command.
  CommandType* = enum
    ctNone,
    ctHeadlines,
    ctSources,
    ctEverything,
    ctHelp,
    ctVersion

  ## Args contains the parsed command-line arguments and options for a
  ## newsapi invocation. The command field identifies which operation to
  ## perform. Remaining fields correspond to API request parameters,
  ## organized by the commands they apply to. The pageSize, page, format,
  ## and outputFile fields apply to all commands. Comments indicate field
  ## sharing across multiple commands.
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

  ## OutputFormat specifies the output format for command results. The
  ## ofMarkdown value produces human-readable formatted output with headers
  ## and structure. The ofJson value outputs compact JSON without
  ## whitespace. The ofJsonPretty value outputs indented JSON with line
  ## breaks for readability.
  OutputFormat* = enum
    ofMarkdown,
    ofJson,
    ofJsonPretty

## showHelp displays usage information including available commands,
## options, environment variables, and examples. The procedure writes the
## help text to standard output and exits with status 0. This is invoked
## when the user specifies --help or -h flags.
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

## getApiKey retrieves the NewsAPI authentication token from the
## NEWSAPI_KEY environment variable. If the variable is unset or empty, the
## procedure writes an error message to standard error and exits with
## status 1. This check ensures all API requests have valid authentication.
proc getApiKey(): string =
  result = getEnv("NEWSAPI_KEY")
  if result == "":
    stderr.writeLine("Error: NEWSAPI_KEY environment variable not set")
    stderr.writeLine("Set it with: export NEWSAPI_KEY=your_api_key")
    quit(1)

## matchCommand resolves a command string to a CommandType value. The
## procedure first checks for exact matches with help and version flags,
## then attempts prefix matching for command names. This enables command
## abbreviation where any unambiguous prefix matches the full command name
## (h for headlines, s for sources, e for everything). Unrecognized inputs
## return ctNone.
proc matchCommand(input: string): CommandType =
  let cmd = input.toLowerAscii()
  
  # Exact matches first
  if cmd in ["--help", "-h", "help"]:
    return ctHelp
  if cmd in ["--version", "-v", "version"]:
    return ctVersion
  
  # Match command abbreviations
  if "headlines".startsWith(cmd):
    return ctHeadlines
  elif "sources".startsWith(cmd):
    return ctSources
  elif "everything".startsWith(cmd):
    return ctEverything
  else:
    return ctNone

## parseArgs processes command-line arguments into an Args object. The
## procedure expects the command as the first parameter followed by option
## flags. It performs command resolution, sets default values for each
## command type, and iterates through options using parseopt. Invalid
## commands, unknown options, and malformed values cause error messages to
## standard error and exit with status 1. The procedure handles both long
## options (--country) and hyphenated variants (--page-size, --pagesize).
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
  
  # Set default pageSize for everything command
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

## articlesToMarkdown converts a sequence of NewsArticle objects to
## markdown-formatted text. Each article becomes a level-2 heading with
## metadata fields (source, author, publication date), description,
## read-more link, and optional image. Articles are separated by horizontal
## rules. Empty fields are omitted from output.
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

## articlesToMarkdown converts a JSON array of article objects to
## markdown-formatted text. This overload operates on JsonNode types for
## cases where JSON parsing is performed directly without deserializing to
## NewsArticle objects. Field extraction uses safe accessors with default
## values for missing data. Output structure matches the NewsArticle
## overload.
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

## sourcesToMarkdown converts a sequence of NewsSource objects to
## markdown-formatted text. Each source becomes a level-2 heading under a
## main "News Sources" title. Metadata includes source identifier, category,
## language, country, description, and website link. Sources are separated
## by horizontal rules. Empty fields are omitted from output.
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

## sourcesToMarkdown converts a JSON array of source objects to
## markdown-formatted text. This overload operates on JsonNode types for
## cases where JSON parsing is performed directly without deserializing to
## NewsSource objects. Field extraction uses safe accessors with default
## values for missing data. Output structure matches the NewsSource
## overload.
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

## outputResult formats and outputs a NewsResponse according to the
## specified format. The markdown format includes a header with total
## result count followed by article listings. JSON formats serialize the
## response object directly. When outputFile is specified, content is
## written to that path with a confirmation message. Otherwise content goes
## to standard output.
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

## outputResult formats and outputs a SourcesResponse according to the
## specified format. The markdown format produces a formatted list of news
## sources with metadata. JSON formats serialize the response object
## directly. When outputFile is specified, content is written to that path
## with a confirmation message. Otherwise content goes to standard output.
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

## outputResult formats and outputs raw JSON response data according to the
## specified format. The markdown format attempts JSON parsing to detect
## response type (articles or sources) and format accordingly. Error
## responses are formatted with code and message. JSON parsing failures
## fall back to raw output. JSON formats output data directly or with
## pretty printing. When outputFile is specified, content is written to
## that path with a confirmation message. Otherwise content goes to
## standard output.
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
        # Check if it's articles or sources response
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

## executeHeadlines performs a top headlines request using parameters from
## the Args object. The procedure validates that either country or sources
## is specified, as required by the API. It constructs a HeadLinesRequest
## with the API key from the environment, executes the request
## asynchronously, and outputs the formatted result. Missing required
## parameters cause error messages to standard error and exit with status 1.
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

## executeSources performs a sources discovery request using parameters
## from the Args object. All parameters are optional, allowing retrieval of
## the complete source catalog or filtered subsets. The procedure
## constructs a SourcesRequest with the API key from the environment,
## executes the request asynchronously, and outputs the formatted result.
proc executeSources(args: Args) {.async.} =
  let req = SourcesRequest(
    apiKey: getApiKey(),
    category: args.category,
    language: args.language,
    country: args.country
  )
  
  let response = await pull(req)
  outputResult(response, args.format, args.outputFile)

## executeEverything performs a comprehensive article search using
## parameters from the Args object. The procedure validates that the query
## parameter is specified, as required by the API. It constructs an
## EverythingRequest with the API key from the environment, executes the
## request asynchronously, and outputs the formatted result. Missing query
## parameter causes an error message to standard error and exit with
## status 1.
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

## showVersion displays the newsapi utility version number to standard
## output and exits with status 0. This is invoked when the user specifies
## --version or -v flags.
proc showVersion() =
  echo "NewsAPI CLI version ", version
  quit(0)

## main is the primary entry point for the newsapi command-line utility.
## The procedure parses command-line arguments, dispatches to the
## appropriate command handler based on the command type, and handles
## special cases for help and version requests. The ctNone case indicates
## an error condition where no valid command was specified. All command
## handlers are invoked asynchronously to support the async API client
## implementation.
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
