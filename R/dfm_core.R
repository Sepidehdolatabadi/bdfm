# m <- 1
# p <- "auto"
# freq <- "auto"
# method = "bayesian"
# Bp <- NULL
# preD <- 1
# lam_B = 0
# trans_df = 0
# Hp = NULL
# lam_H = 0
# obs_df = NULL
# ID = "pc_long"
# store_idx = 1
# reps = 1000
# burn = 500
# verbose = T
# tol = .01
# FC = 3
# # logs = NULL
# # diffs = NULL
# logs = c( 2,  4,  5,  8,  9, 10, 11, 12, 15, 16, 17, 21, 22)
# diffs = c(2, 4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24)
# outlier_threshold <- 4
# scale = TRUE
# orthogonal_shocks = F

dfm_core <- function(Y, m, p, FC = 0, method = "bayesian", scale = TRUE, logs = "auto",
                     outlier_threshold = 4, diffs = "auto", freq = "auto", preD = NULL,
                     Bp = NULL, lam_B = 0, trans_df = 0, Hp = NULL, lam_H = 0, obs_df = NULL, ID = "pc_long",
                     store_idx = NULL, reps = 1000, burn = 500, verbose = TRUE,
                     tol = 0.01, return_intermediates = FALSE, orthogonal_shocks = FALSE) {

  #-------Data processing-------------------------

  data <- Y   # will rename to 'data' later on
  data_orig <- Y

  k <- NCOL(Y) # number of series

  # frequency
  if (freq == "auto") {
    freq <- apply(Y, MARGIN = 2, FUN = get_freq)
  } else if (!is.integer(freq) || length(freq) != ncol(Y)) {
    stop("Argument 'freq' must be 'auto' or integer valued with
         length equal to the number data series")
  }

  if (p == "auto"){
    p <- max(freq)
  }

  # if (FC == "auto"){
  #   FC <- max(freq)
  # }

  # add forecast periods
  if (FC > 0) {
    tmp <- matrix(NA, FC, k)
    Y <- rbind(Y, tmp)
  }


  if((!is.null(logs) && logs == "auto") || (!is.null(diffs) && diffs == "auto")){
    # parse_named_vector <- function(x, name = deparse(substitute(x))) {
    #   z <- paste(paste0("  ", names(x), " = ", x), collapse = ",\n")
    #   paste0(name, " = c(\n", z, "\n)")
    # }
    parse_vector <- function(x, name = deparse(substitute(x))) {
      x.char <- names(x)[x]
      if (length(x.char) == 0) return(paste0(name, " = NULL"))
      z <- paste(paste0("  \"", x.char, "\""), collapse = ",\n")
      paste0(name, " = c(\n", z, "\n)")
    }
    do_log_diff <- should_log_diff(Y)
    if (verbose) message("auto log/diff detection, with:")
    if(logs == "auto"){
      logs <- do_log_diff[1,]
      if (verbose) message(parse_vector(logs), if (diffs == "auto") ",")
    }
    if(diffs == "auto"){
      diffs <- do_log_diff[2,]
      if (verbose) message(parse_vector(diffs))
    }
  }



  if(is.logical(logs)){
    if(!any(logs)) logs <- NULL
  }

  if(is.logical(diffs)){
    if(!any(diffs)) diffs <- NULL
  }


  # logs
  if (!is.null(logs)) {
    logs <- standardize_index(logs, Y)
    Y[, logs] <- log(Y[, logs])
  }

  # differences
  if (!is.null(diffs)) {
    Y_lev <- Y
    diffs <- standardize_index(diffs, Y)
    Y[, diffs] <- sapply(diffs, mf_diff, fq = freq, Y = Y)
  }

  # if (!is.null(trans_df)) {
  #   trans_df <- standardize_index(trans_df, Y)
  # }

  if (!is.null(obs_df)) {
    obs_df <- standardize_numeric(obs_df, Y)
  }

  # specify which series are differenced for mixed frequency estimation

  LD <- rep(0, NCOL(Y))
  if (!is.null(preD)) {
    preD <- standardize_index(preD, Y)
  }
  LD[unique(c(preD, diffs))] <- 1 # in bdfm 1 indicates differenced data, 0 level data

  # drop outliers
  Y[abs(scale(Y)) > outlier_threshold] <- NA

  if (scale) {
    Y <- 100*scale(Y)
    y_scale  <- attr(Y, "scaled:scale")
    y_center <- attr(Y, "scaled:center")
  }

  if (!is.null(store_idx)){
    if(length(store_idx)>1){
      stop("Length of 'store_idx' cannot be greater than 1")
    }
    store_idx <- standardize_index(store_idx, Y)
  }

  if(all(!ID%in%c("pc_wide", "pc_long", "name"))){
    ID <- standardize_index(ID, Y)
  }

  if (length(unique(freq)) != 1 && method != "bayesian") {
    stop("Mixed freqeuncy models are only supported for Bayesian estimation")
  }

  if (method == "bayesian") {
    est <- bdfm(
      Y = Y, m = m, p = p, Bp = Bp,
      lam_B = lam_B, Hp = Hp, lam_H = lam_H, nu_q = trans_df, nu_r = obs_df,
      ID = ID, store_idx = store_idx, freq = freq, LD = LD, reps = reps,
      burn = burn, verbose = verbose, orthogonal_shocks = orthogonal_shocks
    )
  } else if (method == "ml") {
    est <- MLdfm(
      Y = Y, m = m, p = p, tol = tol,
      verbose = verbose, orthogonal_shocks = orthogonal_shocks
    )
  } else if (method == "pc") {
    est <- PCdfm(
      Y, m = m, p = p, Bp = Bp,
      lam_B = lam_B, Hp = Hp, lam_H = lam_H, nu_q = trans_df, nu_r = obs_df,
      ID = ID, reps = reps, burn = burn, orthogonal_shocks = orthogonal_shocks
    )
  }

  # any reason why est$Kstore is in such a strange form? why not simple lists?
  # SL: These objects are arma::field<mat> in the Rcpp code, which works much better
  # than a list internally. As I understand it, in R it is in fact already a list, just
  # one in which all the objects are matrices.
  # k_list <- lapply(seq(NROW(est$Kstore)), function(i) est$Kstore[i, 1, drop = FALSE][[1]])
  # pe_list <- lapply(seq(NROW(est$PEstore)), function(i) est$PEstore[i, 1, drop = FALSE][[1]])
  # gain_list <- lapply(k_list, function(e) t(e[1:m, , drop = FALSE]))

  names_list <- lapply(seq(NROW(Y)), function(i) names(Y[i, ])[is.finite(Y[i, ])])

  factor_update <- Map(
    function(g, pe, nm) {
      x <- g * (matrix(1, NROW(g), 1) %x% t(pe))
      colnames(x) <- nm
      x
    },
    g = est$Kstore,
    pe = est$PEstore,
    nm = names_list
  )

  est$Kstore  <- NULL # this is huge and no longer needed, so drop it
  est$PEstore <- NULL

  # get updates to store_idx if specified
  if(!is.null(store_idx)){
    idx_loading <- est$H[store_idx,,drop=FALSE]%*%J_MF(freq[store_idx], m = m, ld = LD[store_idx], sA = NCOL(est$Jb))
    idx_scale <- if (scale) y_scale[store_idx]/100 else 1
    idx_update <- lapply(factor_update, function(x) as.matrix(idx_scale * (idx_loading %*% x)) )
    # same structure as data: missing values as NA
    idx_update <- lapply(idx_update, function(e){
      tmp <- setNames(rep(NA, k), colnames(Y))
      tmp[colnames(e)] <- e
      return(tmp)
    })
    est$idx_update <- do.call(rbind, idx_update)
  }

  est$factor_update <- lapply(factor_update, function(e) e[1:m,]) #return this instead of gain and prediction error far more useful!

  # undo scaling
  if(scale){
    est$values <- (matrix(1, nrow(est$values), 1) %x% t(y_scale)) * (est$values / 100) + (matrix(1, nrow(est$values), 1) %x% t(y_center))
    est$R2     <- 1 - est$R/10000
    if(!is.null(store_idx) && method == "bayesian"){
      est$Ystore <- est$Ystore*(y_scale[store_idx]/100) + y_center[store_idx]
      est$Ymedain <- est$Ymedian*(y_scale[store_idx]/100) + y_center[store_idx]
    }
  }else{
    est$R2 <- 1 - est$R/apply(X = Y, MARGIN = 2, FUN = var, na.rm = TRUE)
  }

  # undo differences
  if (!is.null(diffs)) {
    est$values[,diffs] <- sapply(diffs, FUN = level, fq = freq, Y_lev = Y_lev, vals = est$values)
    if(!is.null(store_idx) && method == "bayesian" && store_idx%in%diffs){
      est$Ymedain <- level_simple(est$Ymedain, y_lev = Y_lev[,store_idx], fq = freq[store_idx])
      est$Ystore  <- apply(est$Ystore, MARGIN = 2, FUN = level_simple, y_lev = Y_lev[,store_idx], fq = freq[store_idx])
    }
  }

  # undo logs
  if (!is.null(logs)) {
    est$values[,logs] <- exp(est$values[,logs])
    if(!is.null(store_idx) && method == "bayesian" && store_idx%in%logs){
      est$Ymedain <- exp(est$Ymedain)
      est$Ystore  <- exp(est$Ystore)
    }
  }

  #Return intermediate values of low frequency data?
  if (length(unique(freq))>1 && !return_intermediates){
    est$values[,which(freq != 1)] <- do.call(cbind, lapply(X = which(freq != 1), FUN = drop_intermediates,
                                                           freq = freq, Y_raw = Y, vals = est$values))
  }

  est$freq  <- freq
  est$logs  <- logs
  est$diffs <- diffs
  est$scale <- scale
  est$outlier_threshold <- outlier_threshold
  est$differences <- LD

  colnames(est$values) <- colnames(data)

  # adjusted series: align 'values' with original series
  est$adjusted <- align_with_benchmark(est$values, data_orig)

  return(est)
}


# benchmark <- fdeaths
# benchmark[c(1:10, 20:25)] <- NA
# tsbox::ts_plot(mdeaths, fdeaths, aligned = align_with_benchmark(x, benchmark))
align_with_benchmark <- function(x, benchmark) {

  nfct <- NROW(x) - NROW(benchmark)
  if (nfct > 0) {
    benchmark <- rbind(benchmark, matrix(NA_real_, ncol = NCOL(benchmark), nrow = nfct))
  }
  stopifnot(identical(NROW(x), NROW(benchmark)))

  if (NCOL(x) > 1) {  # multivariate mode
    stopifnot(identical(dim(x), dim(benchmark)))
    z <- x
    for (i in 1:NCOL(x)) {
      z[, i] <- align_with_benchmark(x[, i], benchmark[, i])
    }
    return(z)
  }

  dff <- benchmark - x
  dff_approx <- na_appox(dff)
  x + dff_approx
}

