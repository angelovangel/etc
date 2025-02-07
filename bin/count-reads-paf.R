#!/usr/bin/env Rscript

# count PAF reads per reference
# write output to csv

require(vroom)
require(dplyr)
require(optparse)

option_list <- list(
  make_option(
    c("-m", "--mapq"), 
    type = 'integer', 
    default = 60,
    help = "Filter alignments on mapq [default = 60]"),
  make_option(
    c("-f", "--fraction"), 
    type = 'double', 
    default = 0.5, 
    help = "Filter alignments by length (proportion of target len)"
  ),
  make_option(
    c('-p', '--paf'), 
    type = 'character', 
    action = 'store', 
    help = 'Path to PAF file'
  )
)

opts <- parse_args(OptionParser(option_list = option_list))

if (!file.exists(opts$paf) || !is.numeric(opts$mapq)) {
  stop('Parameters are not valid!')
}

paf <- file.path(opts$paf)
bdir <- dirname(tools::file_path_as_absolute(opts$paf))
bname <- tools::file_path_sans_ext(basename(opts$paf))

headers <- c(
  'query', 'query_len', 'query_start', 'query_end', 'strand', 
  'target', 'target_len', 'target_start', 'target_end', 'num_matches', 'align_len', 'mapq'
  )

df <- vroom::vroom(paf, col_names = headers, col_select = all_of(headers))
# mapq is not good for filtering 16S alignments - https://github.com/lh3/minimap2/issues/223

tbl <- 
  df %>%
  dplyr::filter(mapq >= opts$mapq) %>%
  dplyr::filter(align_len/target_len >= opts$fraction) %>%
  group_by(query) %>%
  #mutate(acc = num_matches/align_len) %>% 
  dplyr::filter(row_number() == 1) %>% 
  group_by(target) %>% 
  reframe(target, n =n()) %>% 
  unique() %>% 
  mutate(frac = n/sum(n)) %>%
  arrange(desc(n))

csvfile <- file.path(bdir, paste0(bname, '.csv'))
write.csv(tbl, file = csvfile, row.names = F, quote = FALSE)

print(paste0('CSV file written: ', csvfile))
print(paste0('Total alignments written: ', sum(tbl$n, na.rm = T)))
print(paste0('Total targets: ', length(unique(tbl$target)), " (out of ", length(unique(df$target)), ")"))

