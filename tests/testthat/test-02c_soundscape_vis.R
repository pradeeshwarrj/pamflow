test_that("pam_soundscape_plot_diel creates ggplot object", {
  hourly_dt <- data.table::data.table(
    grid = rep(c("G01", "G02"), each = 24),
    hour = rep(0:23, 2),
    aci_mean = runif(48, 100, 200),
    aci_sd = runif(48, 5, 15),
    bio_mean = runif(48, 2, 8),
    bio_sd = runif(48, 0.5, 1.5)
  )

  p_list <- pam_soundscape_plot_diel(hourly_dt)
  expect_type(p_list, "list")
  expect_named(p_list, c("aci", "bio"))
  expect_s3_class(p_list$aci, "ggplot")
})

test_that("pam_soundscape_plot_phase creates ggplot object", {
  diel_dt <- data.table::data.table(
    grid = rep(c("G01", "G02"), each = 2),
    diel_phase = rep(c("Day", "Night"), 2),
    aci_mean = c(150, 120, 160, 110),
    aci_sd = c(10, 8, 12, 9),
    bio_mean = c(5, 2, 6, 3),
    bio_sd = c(1, 0.5, 1.2, 0.6)
  )

  p_list <- pam_soundscape_plot_phase(diel_dt)
  expect_type(p_list, "list")
  expect_named(p_list, c("aci", "bio"))
  expect_s3_class(p_list$aci, "ggplot")
})
