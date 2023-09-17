#!/usr/bin/env Rscript

# count PAF reads per reference
# write output to csv

require(vroom)
require(dplyr)

arg <- commandArgs(trailingOnly = TRUE)
if( length(arg) != 1 ) { stop(" Incorrect number of arguments") }

paf <- file.path(arg[1])
bdir <- dirname(tools::file_path_as_absolute(arg[1]))
bname <- tools::file_path_sans_ext(basename(arg[1]))

headers <- c(
  'query', 'query_len', 'query_start', 'query_end', 'strand', 
  'target', 'target_len', 'target_start', 'tartget_end', 'num_matches', 'align_len', 'mapq'
  )

df <- vroom::vroom(paf, col_names = headers, col_select = all_of(headers))
df %>%
  dplyr::filter(mapq >= 50) %>% 
  #dplyr::mutate(acc =num_matches/align_len ) %>%
  group_by(target) %>% 
  summarise(n = n()) %>%
  ungroup() %>%
  mutate(frac = n/sum(n)) %>%
  arrange(desc(n)) %>%
  write.csv(file = file.path(bdir, paste0(bname, '.csv')), row.names = F, quote = FALSE)
