source("scripts/00_setup.R")
estimates <- read_table("out/tab/estimates.csv")
sampled <- estimates |>
  filter(!region_id %in% c("blr", "maa", "mys"), estimator == "unweighted") |>
  mutate(district = unname(region_names[region_id]))
order <- sampled |>
  filter(group == "any") |>
  arrange(p) |>
  pull(district)
sampled <- sampled |> mutate(district = factor(district, levels = order))
plot <- sampled |>
  filter(group == "any") |>
  ggplot(aes(x = p, y = district)) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high), linewidth = 0.5) +
  geom_point(size = 2.4, colour = "#176B75") +
  scale_x_continuous(
    labels = scales::label_percent(accuracy = 1),
    breaks = seq(0, 0.12, 0.02), limits = c(0, NA)
  ) +
  labs(
    title = "Confirmed identity branding in captured restaurant names",
    subtitle = "Eight district collections, 2026", x = "Share of captured listings", y = NULL,
    caption = paste(
      "Points: confirmed shares. Lines: conditional 95% bootstrap intervals (2,000 draws).",
      "All 400 query points per district are resampled using retained first-capture assignments.",
      paste(
        "Intervals exclude coverage and label uncertainty;",
        "unresolved-hit bounds are reported separately."
      ),
      sep = "\n"
    )
  ) +
  theme_evidence()
save_figure(plot, "district_prevalence", 8, 5.5)
plot <- sampled |>
  filter(group != "any") |>
  mutate(category = factor(unname(group_names[group]), levels = unname(group_names[-1]))) |>
  ggplot(aes(x = p, y = district)) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high), linewidth = 0.4, na.rm = TRUE) +
  geom_point(size = 2, colour = "#176B75") +
  facet_wrap(vars(category), nrow = 1) +
  scale_x_continuous(
    labels = scales::label_percent(accuracy = 1),
    breaks = seq(0, 0.12, 0.02), limits = c(0, NA)
  ) +
  labs(
    title = "The form of identity branding varies across districts",
    x = "Share of captured listings", y = NULL,
    caption = paste(
      "Denominator: all captured restaurants in each district. Categories can overlap.",
      "Lines: conditional 95% query-point bootstrap intervals; omitted for zero counts.",
      "Labels describe signboards, not owners' caste. Intervals exclude classification error.",
      sep = "\n"
    )
  ) +
  theme_evidence()
save_figure(plot, "branding_composition", 11, 5.5)
