#' @include optim.R
NULL

optim_Rprop <- R6::R6Class(
  "optim_rprop",
  lock_objects = FALSE,
  inherit = Optimizer,
  public = list(
    initialize = function(params, lr=1e-2, etas=c(0.5, 1.2), step_sizes=c(1e-6, 50)){
      if (lr < 0)
        value_error("Invalid learning rate: {lr}")
      if (etas[[1]] < 0 || etas[[1]] > 1.0 || etas[[2]] < 1)
        value_error("Invalid eta values: {etas[[1]]}, {etas[[2]]}")
      defaults <- list(lr=lr, etas=etas, step_sizes=step_sizes)
      super$initialize(params, defaults)
    }, 
    
    step = function(closure = NULL) {
      with_no_grad({
        
        loss <- NULL
        if (!is.null(closure)) {
          with_enable_grad({
            loss <- closure()
          })
        }
        
        for (g in seq_along(self$param_groups)) {
          
          group <- self$param_groups[[g]]
          
          for (p in seq_along(group$params)) {
            
            param <- group$params[[p]]
            
            if (is.null(param$grad) || is_undefined_tensor(param$grad))
              next
            
            grad  <- param$grad

            if (length(param$state) == 0) {
              param$state <- list()
              param$state[["step"]] <- 0
              param$state[["prev"]] <- torch_zeros_like(param, memory_format=torch_preserve_format())
              new_tensor <- torch_zeros_like(grad, memory_format=torch_preserve_format())
              param$state[["step_size"]] <-  new_tensor$resize_as_(grad)$fill_(group[["lr"]])
            }
            
            etaminus <-  group[["etas"]][[1]]
            etaplus  <-  group[["etas"]][[2]]

            step_size_min <- group[["step_sizes"]][[1]]
            step_size_max <- group[["step_sizes"]][[2]]

            step_size <- param$state[["step_size"]]
            
            param$state[['step']] <- param$state[['step']] + 1

            sign <- grad$mul(param$state[["prev"]])$sign()
            sign[sign$gt(0)] <- etaplus
            sign[sign$lt(0)] <- etaminus
            sign[sign$eq(0)] <- 1
            
            # update stepsizes with step size updates
            step_size$mul_(sign)$clamp_(step_size_min, step_size_max)
            
            # for dir<0, dfdx=0
            # for dir>=0 dfdx=dfdx
            grad <- grad$clone(memory_format=torch_preserve_format())
            grad[sign$eq(etaminus)] <- 0
            
            # update parameters
            param$addcmul_(grad$sign(), step_size, value=-1)
            
            param$state[["prev"]]$copy_(grad)
          }
        }
      })
      loss
    }
  )
)

#' Implements the resilient backpropagation algorithm.
#' 
#' Proposed first in [RPROP - A Fast Adaptive Learning Algorithm](http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.52.4576)
#' 
#' @param params (iterable): iterable of parameters to optimize or lists defining
#' parameter groups
#' @param lr (float, optional): learning rate (default: 1e-2)
#' @param etas (Tuple(float, float), optional): pair of (etaminus, etaplis), that
#' are multiplicative increase and decrease factors
#' (default: (0.5, 1.2))
#' @param step_sizes (vector(float, float), optional): a pair of minimal and
#' maximal allowed step sizes (default: (1e-6, 50))
#' 
#' @examples
#' \dontrun{
#' optimizer <- optim_rprop(model$parameters(), lr=0.1)
#' optimizer$zero_grad()
#' loss_fn(model(input), target)$backward()
#' optimizer$step()
#' }
#' 
#' @export
optim_rprop <- function(params, lr=1e-2, etas=c(0.5, 1.2), step_sizes=c(1e-6, 50)){
  optim_Rprop$new(params, lr, etas, step_sizes)
}

