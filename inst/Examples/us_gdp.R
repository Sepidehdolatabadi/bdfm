library(bdfm)

# drop outliers (optional but gets rid of some wierd stuff)
econ_us[abs(scale(econ_us)) > 4] <- NA

logs <- c(
  "W068RCQ027SBEA",
  "PCEDG",
  "PCEND",
  "JTSJOL",
  "INDPRO",
  "CSUSHPINSA",
  "HSN1F",
  "TSIFRGHT",
  "IPG2211S",
  "DGORDER",
  "AMTMNO",
  "CPILFESL",
  "ICSA"
)

diffs <- setdiff(colnames(econ_us), c("A191RL1Q225SBEA", 'W068RCQ027SBEA', "USSLIND"))

m <- dfm(
  econ_us,
  obs_df = c("A191RL1Q225SBEA" = 1),
  factors = 2,
  pre_differenced = "A191RL1Q225SBEA",
  logs = logs,
  diffs = diffs
)

# Are we drawing from a stationary distribution?
ts.plot(m$Qstore[1,1,])
ts.plot(m$Hstore[1,1,])

summary(m)

