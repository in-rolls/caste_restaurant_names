region_names <- c(
  blr = "Bengaluru", maa = "Chennai", mys = "Mysuru", blr2 = "Bengaluru",
  maa2 = "Chennai", mys2 = "Mysuru", del = "Delhi", jai = "Jaipur", kol = "Kolkata",
  lko = "Lucknow", vns = "Varanasi"
)
group_names <- c(
  any = "Any identity marker", regional = "Regional / cuisine",
  surname_title = "Surname / title", merchant_community = "Merchant community",
  upper_caste = "Explicit upper-caste label"
)

theme_evidence <- function() {
  ggplot2::theme_minimal(base_size = 11, base_family = "sans") +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_blank(),
      axis.text = ggplot2::element_text(colour = "#222222"),
      plot.title = ggplot2::element_text(face = "bold"),
      plot.title.position = "plot", plot.caption.position = "plot",
      plot.caption = ggplot2::element_text(hjust = 0, size = 9),
      strip.text = ggplot2::element_text(face = "bold"),
      plot.margin = ggplot2::margin(12, 20, 12, 12)
    )
}

save_figure <- function(plot, name, width, height) {
  for (extension in c("png", "pdf")) {
    ggplot2::ggsave(file.path("out/fig", paste0(name, ".", extension)),
      plot = plot, width = width, height = height, units = "in", dpi = 180, bg = "white"
    )
  }
}
