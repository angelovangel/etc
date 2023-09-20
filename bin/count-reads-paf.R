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
# mapq is not good for filtering 16S alignments - https://github.com/lh3/minimap2/issues/223

tbl <- 
  df %>%
  group_by(query) %>%
  mutate(acc = num_matches/align_len) %>% 
  dplyr::filter(row_number() == 1) %>% 
  group_by(target) %>% 
  reframe(target, n =n()) %>% 
  unique() %>% 
  mutate(frac = n/sum(n)) %>%
  arrange(desc(n))

write.csv(tbl, file = file.path(bdir, paste0(bname, '.csv')), row.names = F, quote = FALSE)


print(paste0('Total reads: ', sum(tbl$n, na.rm = T)))

