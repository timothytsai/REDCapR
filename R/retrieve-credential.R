#' @name retrieve_credential
#' @aliases retrieve_credential_local retrieve_credential_mssql
#' @export retrieve_credential_local retrieve_credential_mssql
#' @title Read a token and other credentials from a (non-REDCap) database or file.
#'
#' @description These functions are not essential to calling the REDCap API, but instead are functions that help manage tokens securely.
#'
#' @usage
#' retrieve_credential_local(
#'   path_credential, project_id, check_url=TRUE,
#'   check_username=FALSE, check_token_pattern=TRUE
#' )
#' retrieve_credential_mssql(
#'   project_id, instance, dsn, channel=NULL
#' )
#'
#' @param path_credential The file path to the CSV containing the credentials. Required.
#' @param project_id The ID assigned to the project withing REDCap.  This allows the user to store tokens to multiple REDCap projects in one file.  Required
#' @param instance The casual name associated with the REDCap instance on campus.  This allows one credential system to accommodate multiple instances on campus.  Required
#' @param check_url A `logical` value indicates if the url in the credential file should be checked to have approximately the correct form.  Defaults to TRUE.
#' @param check_username A `logical` value indicates if the username in the credential file should be checked against the username returned by R.  Defaults to FALSE.
#' @param check_token_pattern A `logical` value indicates if the token in the credential file is a 32-character hexadecimal string.  Defaults to FALSE.
#' @param dsn A [DSN](http://en.wikipedia.org/wiki/Data_source_name) on the local machine that points to the desired MSSQL database. Required.
#' @param channel An *optional* connection handle as returned by [DBI::dbConnect()].  See Details below. Optional.
#'
#' @return A list of the following elements
#' * `redcap_uri`: The URI of the REDCap Server.
#' * `username`: Username.
#' * `project_id`: The ID assigned to the project withing REDCap.
#' * `token`: The token to pass to the REDCap server
#' * `comment`: An optional string.
#'
#' @details
#' If the database elements are created with the script provided in package's 'Security Database' vignette, the default values will work.
#'
#' @note
#' Although we strongly encourage storing all the tokens on a central server (*e.g.*, see the
#' `retrieve_credential_mssql()` function and the "SecurityDatabase" vignette), there are times
#' when this approach is not feasible and the token must be stored locally.  Please contact us
#' if your institution is using something other than SQL Server, and
#' would like help adapting this approach to your infrastructure.
#'
#' @author Will Beasley
#'
#' @examples
#' # ---- Local File Example ----------------------------
#' path <- system.file("misc/example.credentials", package="REDCapR")
#' (p1  <- REDCapR::retrieve_credential_local(path, 153L))
#' (p2  <- REDCapR::retrieve_credential_local(path, 212L))

retrieve_credential_local <- function(
  path_credential,
  project_id,
  check_url                = TRUE,
  check_username           = FALSE,
  check_token_pattern      = TRUE
) {

  checkmate::assert_character(path_credential           , any.missing=F, len=1, pattern="^.{1,}$")
  checkmate::assert_file_exists(path_credential                                                  )

  col_types <- readr::cols_only(
    redcap_uri    = readr::col_character(),
    username      = readr::col_character(),
    project_id    = readr::col_integer(),
    token         = readr::col_character(),
    comment       = readr::col_character()
  )

  ds_credentials <- readr::read_csv(path_credential, col_types=col_types, comment="#")

  # Check that it's a data.frame with valid variable names
  if( !inherits(ds_credentials, "data.frame") ) {
    stop("The credentials file was not correctly transformed into a [base::data.frame()].  Make sure it's a well-formed CSV.")
  } else if ( !identical(colnames(ds_credentials), c("redcap_uri", "username", "project_id", "token", "comment")) ) {
    stop("The credentials file did not contain the proper variables of `redcap_uri`, `username`, `project_id`, `token`,  and `comment`.")
  }

  # Select only the records with a matching project id.
  ds_credential <- ds_credentials[ds_credentials$project_id==project_id, ]

  # Check that one and only one record matches the project id.
  if( nrow(ds_credential)==0L ) {
    stop("The project_id was not found in the csv credential file.")
  } else if( nrow(ds_credential) > 1 ) {
    stop("More than one matching project_id was found in the csv credential file.  There should be only one.")
  } else {
    credential <- list(
      redcap_uri   = ds_credential$redcap_uri[1],
      username     = ds_credential$username[1],
      project_id   = ds_credential$project_id[1],
      token        = ds_credential$token[1],
      comment      = ds_credential$comment[1]
    )
  }

  # Progress through the optional checks
  if( check_url & !grepl("https://", credential$redcap_uri, perl=TRUE) ) {
    error_message_username <- paste(
      "The REDCap URL does not reference an https address.  First check",
      "that the URL is correct, and then consider using SSL to encrypt",
      "the REDCap webserver.  Set the `check_url` parameter to FALSE",
      "if you're sure you have the correct file & file contents."
    )
    stop(error_message_username)

  } else if( check_username & (Sys.info()["user"]!=credential$username) ) {
    error_message_username <- paste(
      "The username (according to R's `Sys.info()['user']` doesn't match the",
      "username in the credentials file.  This is a friendly check, and",
      "NOT a security measure.  Set the `check_username` parameter to FALSE",
      "if you're sure you have the correct file & file contents.",
      "Otherwise, you may be pointing to the wrong credentials file."
    )
    stop(error_message_username)

  } else if( check_token_pattern & !grepl("[A-F0-9]{32}", credential$token, perl=TRUE) ) {
    error_message_token <- paste(
      "A REDCap token should be a string of 32 digits and uppercase",
      "characters.  The retrieved value was not.",
      "Set the `check_token_pattern` parameter to FALSE",
      "if you're sure you have the correct file & file contents."
    )
    stop(error_message_token)

  }

  # Return to caller.
  return( credential )
}

retrieve_credential_mssql <- function(
  project_id,
  instance,
  dsn                      = NULL,
  channel                  = NULL
) {

  if( !requireNamespace("DBI")  ) stop("The function REDCapR::retrieve_credential_mssql() cannot run if the `DBI` package is not installed.  Please install it and try again.")
  if( !requireNamespace("odbc") ) stop("The function REDCapR::retrieve_credential_mssql() cannot run if the `odbc` package is not installed.  Please install it and try again.")

  regex_pattern_1 <- "^\\d+$"
  regex_pattern_2 <- "^\\[*[a-zA-Z0-9_]+\\]*$"

  # checkmate::assert_integer(project_id, any.missing=F, len=1L, lower=1L)
  if( class(project_id)  != "integer" )
    stop("The `project_id` parameter be an integer type.  Either append an `L` to the number, or cast with `as.integer()`.")
  if( class(instance)  != "character" )
    stop("The `instance` parameter be a character type.  Either enclose in quotes, or cast with `as.character()`.")
  if( !(base::missing(dsn) | base::is.null(dsn)) & !(class(dsn) %in% c("character")) )
    stop("The `dsn` parameter be a character type, or missing or NULL.  Either enclose in quotes, or cast with `as.character()`.")
  # if( !(base::missing(channel) | base::is.null(channel))  & !inherits(channel, "DBIConnection") )
  if( !(base::missing(channel) | base::is.null(channel)) & !methods::is(channel, "DBIConnection") )
    stop("The `channel` parameter be a `DBIConnection` connection type, or NULL.")

  if( length(project_id) != 1L )
    stop("The `project_id` parameter should contain exactly one element.")
  if( length(instance) != 1L )
    stop("The `instance` parameter should contain exactly one element.")
  if( length(dsn) > 1L )
    stop("The `dsn` parameter should contain at most one element.")
  if( length(channel) > 1L )
    stop("The `channel` parameter should contain at most one element.")

  if( !grepl(regex_pattern_1, project_id) )
    stop("The 'project_id' parameter must contain at least one digit, and only digits.")
  if( !grepl(regex_pattern_2, instance) )
    stop("The 'instance' parameter must contain only letters, numbers, and underscores.  It may optionally be enclosed in square brackets.")


  sql <- "EXEC [redcap].[prc_credential] @project_id = ?, @instance = ?"
  input <- list(project_id = project_id, instance = instance)

  # d_input <- data.frame(
  #   project_id         = project_id,
  #   instance           = instance,
  #   stringsAsFactors   = FALSE
  # )

  if( base::missing(channel) | base::is.null(channel) ) {
    if( base::missing(dsn) | base::is.null(dsn) )
      stop("The 'dsn' parameter can be missing only if a 'channel' has been passed to 'retrieve_credential_mssql'.")

    # channel <- RODBC::odbcConnect(dsn=dsn)
    channel <- DBI::dbConnect(odbc::odbc(), dsn=dsn)
    close_channel_on_exit <- TRUE
  } else {
    close_channel_on_exit <- FALSE
  }

  base::tryCatch(
    expr = {
      # ds_credential <- RODBCext::sqlExecute(channel, sql, d_input, fetch=TRUE, stringsAsFactors=FALSE)
      result        <- DBI::dbSendQuery(channel, sql)
      DBI::dbBind(result, input)
      d_credential  <- DBI::dbFetch(result)
    }, finally = {
      # if( close_channel_on_exit ) RODBC::odbcClose(channel)
      if( !is.null(result))       DBI::dbClearResult(result)
      if( close_channel_on_exit ) DBI::dbDisconnect(channel)
    }
  )

  if( nrow(d_credential) == 0L ) {
    stop(paste("The REDCap token for project", project_id, "was not found on for this username and instance.  Please verify with your REDCap admin that you have both (a) API rights AND (b) an API token generated."))
  } else if( nrow(d_credential) >= 2L ) {
    stop("No more than one row should be retrieved from the credentials.  The [username]-by-[instance]-by-[project_id] should be unique in the table.")
  }

  # browser()
  credential <- list(
    redcap_uri   = d_credential$redcap_uri,
    username     = d_credential$username,
    project_id   = d_credential$project_id,
    token        = d_credential$token,
    comment      = ""
  )

  return( credential )
}
# credential <- REDCapR::retrieve_credential_mssql(dsn="BbmcSecurity", project_id=404L, instance='bbmc')
# ds <- REDCapR::redcap_read(redcap_uri=credential$redcap_uri, token=credential$token)$data
