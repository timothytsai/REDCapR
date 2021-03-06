library(testthat)
context("Read Superwide")

credential <- REDCapR::retrieve_credential_local(
  path_credential = system.file("misc/example.credentials", package="REDCapR"),
  project_id      = 753
)


test_that("smoke test", {
  testthat::skip_on_cran()
  expect_message(
    returned_object <- redcap_read_oneshot(redcap_uri=credential$redcap_uri, token=credential$token, verbose=T)
  )
})

test_that("correct dimensions -oneshot", {
  testthat::skip_on_cran()
  expected_outcome_message <- "2 records and 3,004 columns were read from REDCap in \\d+(\\.\\d+\\W|\\W)seconds\\."

  expected_row_count <- 2L
  expected_column_count <- 3000L + 4L # 3,000 variables, plus `record_id` and three `form_q_complete`

  expect_message(
    regexp           = expected_outcome_message,
    returned_object <- redcap_read_oneshot(redcap_uri=credential$redcap_uri, token=credential$token, verbose=T)
  )

  expect_equal(nrow(returned_object$data), expected=expected_row_count) # dput(returned_object$data)
  expect_equal(ncol(returned_object$data), expected=expected_column_count)
  expect_false(any(is.na(returned_object$data)))

  expect_equal(returned_object$status_code, expected=200L)
  expect_equivalent(returned_object$raw_text, expected="") # dput(returned_object$raw_text)
  expect_true(returned_object$records_collapsed=="", "A subset of records was not requested.")
  expect_true(returned_object$fields_collapsed=="", "A subset of fields was not requested.")
  expect_true(returned_object$filter_logic=="", "A filter was not specified.")
  expect_match(returned_object$outcome_message, regexp=expected_outcome_message, perl=TRUE)
  expect_true(returned_object$success)
})

test_that("correct dimensions -batch", {
  testthat::skip_on_cran()
  expected_outcome_message <- "2 records and 3,004 columns were read from REDCap in \\d+(\\.\\d+\\W|\\W)seconds\\."

  expected_row_count <- 2L
  expected_column_count <- 3000L + 4L # 3,000 variables, plus `record_id` and three `form_q_complete`

  expect_message(
    regexp           = expected_outcome_message,
    returned_object <- redcap_read(redcap_uri=credential$redcap_uri, token=credential$token, verbose=T)
  )

  expect_equal(nrow(returned_object$data), expected=expected_row_count) # dput(returned_object$data)
  expect_equal(ncol(returned_object$data), expected=expected_column_count)
  expect_false(any(is.na(returned_object$data)))

  expect_true(  returned_object$success)
  expect_match( returned_object$status_codes, regexp="200", perl=TRUE)
  expect_true(  returned_object$records_collapsed=="", "A subset of records was not requested.")
  expect_true(  returned_object$fields_collapsed=="", "A subset of fields was not requested.")
  expect_true(  returned_object$filter_logic=="", "A filter was not specified.")
  expect_match( returned_object$outcome_messages, regexp=expected_outcome_message, perl=TRUE)
})
