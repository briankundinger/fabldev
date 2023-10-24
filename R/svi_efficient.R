svi_efficient <- function(hash, threshold = 1e-5, tmax = 1000, fixed_iterations = NULL,
                           b_init = TRUE, B = min(1000, hash$n2), holdout_size = min(1000, hash$n2),
                          k = 1, tau = 1, seed = 0){

  set.seed(seed)
  check_every <- 10

  ohe <- hash$ohe # One-hot encodings e(h_p)
  P <- dim(ohe)[1]
  total_counts <- hash$total_counts #N_p
  pattern_counts_by_record <- hash$pattern_counts_by_record #N_p_j
  record_counts_by_pattern <- hash$record_counts_by_pattern
  field_marker <- hash$field_marker
  n1 <- hash$n1
  n2 <- hash$n2

  # Priors
  alpha <- rep(1, length(field_marker))
  Beta <- rep(1, length(field_marker))
  alpha_pi <- 1
  beta_pi <- 1

  # Initialize
    a <- rep(1, length(field_marker))
  if(b_init == T){
    b <- hash$ohe %>%
      sweep(., 1, hash$total_counts, "*") %>%
      colSums()
  } else {
    b = rep(1, length(field_marker))
  }
    a_pi <- 1
    b_pi <- 1

  t <- 1
  ratio <- 1
  elbo_seq <- vector()
  adjustment <- n2 / B
  #tao <- 1
  #k <- 1

  holdout <- sample(1:n2, holdout_size)

  while(t <= tmax){
    a_sum <- a %>%
      split(., field_marker) %>%
      sapply(., sum) %>%
      digamma(.) %>%
      .[field_marker]

    a_chunk <- digamma(a) - a_sum

    b_sum <- b %>%
      split(., field_marker) %>%
      sapply(., sum) %>%
      digamma(.) %>%
      .[field_marker]
    b_chunk <- digamma(b) - b_sum

    m_p <- ohe %>%
      sweep(., 2, a_chunk, "*") %>%
      rowSums()

    u_p <- ohe %>%
      sweep(., 2, b_chunk, "*") %>%
      rowSums()

    # w_p
    weights = m_p - u_p

    # phi_single
    phi <- exp(digamma(a_pi) - digamma(n1) + weights)
    single <- exp(digamma(b_pi))

    # Phi_j
    batch <- sample(1:n2, B, replace = F)
    C <- sapply(batch, function(x){
      pattern_counts_by_record[[x]] %*% phi + single
    })

    # S(Phi)
    total_nonmatch <- adjustment * sum(single/ C)
    total_counts <- lapply(batch, function(x){
      hash$pattern_counts_by_record[[x]]
    }) %>%
      do.call(rbind, .) %>%
      colSums() * adjustment

    # N_p(Psi)
    K <- sapply(1:P, function(p){
      sum(record_counts_by_pattern[[p]][batch]/C)
    }) * adjustment

    epsilon <- (t + tao) ^ (-k)

    AZ <- ohe %>%
      sweep(., 1, phi * K, "*") %>%
      colSums()

    BZ <- ohe %>%
      sweep(., 1, total_counts - (phi * K), "*") %>%
      colSums()

    a <- (1 - epsilon) * a + epsilon * (alpha + AZ)
    b <- (1 - epsilon) * b + epsilon * (Beta + BZ)

    a_pi <- (1 - epsilon) * a_pi  +
      epsilon * (alpha_pi + n2 - total_nonmatch)
    b_pi <- (1 - epsilon) * b_pi +
      epsilon * (beta_pi + total_nonmatch)

    # ELBO
    elbo_pieces <- vector(length = 6)
    C_holdout <- sapply(holdout, function(x){
      pattern_counts_by_record[[x]] %*% phi + single
    })

    holdout_nonmatch <- n2/holdout_size * sum(single/ C_holdout)
    # elbo_pieces[1] <- sapply(seq_along(holdout), function(j){
    #   record <- batch[j]
    #   sum(pattern_counts_by_record[[record]] * (phi *(weights - log(phi) + log(C[j]))/ C[j] +
    #                                          u_p))
    # }) %>%
    #   sum(.) * adjustment
    #
    # elbo_pieces[2] <-  single * adjustment * sum(1/C *log(C)) + total_nonmatch * log(n1) -log(n1)*n2
    #
    elbo_pieces[1] <- sapply(seq_along(holdout), function(j){
      record <- holdout[j]
      sum(pattern_counts_by_record[[record]] * (phi *(weights - log(phi) + log(C_holdout[j]))/ C_holdout[j] +
                                                  u_p))
    }) %>%
      sum(.) * n2/ holdout_size

    elbo_pieces[2] <-  n2/ holdout_size * single * sum(1/C_holdout *log(C_holdout)) + holdout_nonmatch * (log(n1) - log(single)) -log(n1)*n2


    elbo_pieces[3] <- lbeta(a_pi, b_pi) - lbeta(alpha_pi, beta_pi)


    elbo_pieces[4] <- sapply(list(a, b), function(y){
      split(y, field_marker) %>%
        sapply(., function(x){
          sum(lgamma(x)) - lgamma(sum(x))
        })%>%
        sum(.)
    }) %>%
      sum(.)

    elbo_pieces[5] <- -sapply(list(alpha, Beta), function(y){
      split(y, field_marker) %>%
        sapply(., function(x){
          sum(lgamma(x)) - lgamma(sum(x))
        })%>%
        sum(.)
    }) %>%
      sum(.)

    elbo_pieces[6] <- sum((alpha - a) * a_chunk + (Beta - b) * b_chunk)
    elbo <- sum(elbo_pieces)
    elbo_seq <- c(elbo_seq, elbo)


    if(is.null(fixed_iterations)){
      if(t %% check_every == 0){
        ratio <- abs((elbo_seq[t] - elbo_seq[t - check_every +1])/
                       elbo_seq[t - check_every +1])
      }
      if(ratio < threshold){
        break
      }
    }

    t <- t + 1
    if(t > tmax){
      print("Max iterations have passed before convergence")
      break
    }

    if(!is.null(fixed_iterations)){
      if(t == fixed_iterations){
        break
      }
    }


  }

  C <- sapply(1:n2, function(x){
    pattern_counts_by_record[[x]] %*% phi + single
  })

  list(pattern_weights = phi,
       C = C,
       a = a,
       b = b,
       a_pi = a_pi,
       b_pi = b_pi,
       elbo_seq = elbo_seq,
       t = t)

}
