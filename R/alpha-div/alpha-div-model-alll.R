
## alpha diversity - model all indices and correct for multiple comps

# EVS 2/2022

require(tidyverse)
require(phyloseq)
require(microViz)
require(rstatix)
require(ggpubr)

load("./data/ps-decontam-filtered-counts.RData")

## remove Males
pscount <- pscount %>% ps_filter(!Treatment == "Males")

# get sample data
sampdf <- sample_data(pscount) %>% 
  data.frame() %>% 
  rownames_to_column(var = "ID") %>% 
  # add Age
  mutate(Age = recode_factor(
    Sample.Date,
    "8/8/19" = "40 weeks",
    "10/16/19" = "50 weeks",
    "12/20/19" = "60 weeks",
    .ordered = TRUE
  ))

# get diversity
alpha <- estimate_richness(pscount) %>% 
  # make ID
  rownames_to_column(var = "ID") %>% 
  merge(sampdf, by = "ID") 

# make vertical
alphav <- alpha %>% 
  select(-c(se.chao1, se.ACE)) %>% 
  pivot_longer(cols = c("Observed", "Chao1", "ACE", "Shannon",
                        "Simpson", "InvSimpson", "Fisher"),
               names_to = "index", values_to = "values") %>% 
  # remove Observed (not good to statistically compare) %>% 
  filter(!index == "Observed") %>% 
  # recode Treatment
  mutate(treat.rec = recode_factor(Treatment,
                                   Control = "0 mg/kg",
                                   T2 = "25 mg/kg",
                                   T3 = "50 mg/kg",
                                   T4 = "75 mg/kg"))

## ---- summary stats ----

sum <- alphav %>% group_by(index, treat.rec, Age) %>% 
  get_summary_stats(values, type = "common") %>% 
  select(-c(variable, mean, sd, se, ci))

write.table(sum, file = "data/alpha-div-summary-stats.txt", sep = "\t", row.names = FALSE)

## ---- loop through all tests ----

# loop for all 3 models
inds <- unique(alphav$index)
outdf <- data.frame()
for(i in 1:length(inds)) {
  
  # plot histogram of raw data
  p <- ggdensity(filter(alphav, index == inds[i]),
              x = "values") +
    ggtitle(inds[i])
  print(p)
  
  # MODEL 1: Treatment v control
  mod1 <- wilcox_test(
    data = filter(alphav,
                  Treatment %in% c("Control", "T4") & index == inds[i]),
    formula = values ~ Treatment
  ) %>% 
    mutate(index = inds[i],
           model = "Control_T4") %>% 
    # force to fit with KW tests
    select(.y., statistic, p, index, model) %>% mutate(method = "wilcox", 
                                                       n = "NA",
                                                       df = "NA")
  
  # MODEL 2: Time difference
  mod2 <- kruskal_test(
    data = filter(alphav,
                  Treatment %in% c("T2", "T3", "T4") & index == inds[i]),
    formula = values ~ Sample.Date
  ) %>% 
    mutate(index = inds[i],
           model = "Time")
  
  # MODEL 3: dose response
  mod3 <- kruskal_test(
    data = filter(alphav,
                  Treatment %in% c("T2", "T3", "T4") & index == inds[i]),
    formula = values ~ Treatment
  )   %>% 
    mutate(index = inds[i],
             model = "Dose")
  
  # save to outdf
  outdf <- rbind(mod1, mod2, mod3, outdf)
}

# correct for multiple comparisons
sigs <- outdf %>% 
  mutate(padj = p.adjust(p, method = "fdr"))

## bonferroni correction by hand
alpha <- 0.05/nrow(outdf) # this is the new alpha
outdf %>% filter(p < alpha) # none


# get significant
sigs %>% filter(padj < 0.05) # NONE

# get unadjusted significant
sigs %>% filter(p < 0.05)

