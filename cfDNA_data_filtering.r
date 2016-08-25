############################################################################
#
#                     ctDNA Data Filtering
#
# Author: Olena Kis
# Last Modified: July 6, 2016
# Date Created: May 26, 2015

###############################
#         Variables
###############################

myarg <- commandArgs(trailingOnly=TRUE)
file.path <- myarg[1]
file.ext <- ".maf"
projectname <- myarg[2]

# Strand bias filter
LODfwd_rev_ratio_thr <- 5  # highest allowable fold difference between forward and reverse LOD scores
# Tumor LOD score filter
LOD_Zscore_thresh <- 20  # determined using ROC_curve_LOD_score.R script
# Threshold allele frequency in 1000 Genomes data used to call a variant as a germline SNP
X1000Gen_thresh <- 0.001  ## Filters based on >= 0.1% frequency in normal population
# Specify minimum fraction of total reads which has to be used as supporting reads (Alt + Ref count) to call a mutations
Fraction_supp_reads <- 0.1 # the sum of ref_allele_counts and alt_allele counts should be at least 10% of total reads

summary_vect <- c("Sample_ID",
                  "Genome_Change",
                  "Hugo_Symbol",
                  "Protein_Change",
                  "UniProt_AApos",
                  "Variant_Classification",
                  "cDNA_Change",
                  "t_alt_count",
                  "t_ref_count",
                  "total_pairs",
                  "fraction_supp_reads",
                  "tumor_f",
                  "t_lod_fstar",
                  "modified_Z_score",
                  "t_lod_fstar_forward",
                  "t_lod_fstar_reverse",
                  "skew1",
                  "skew2",
                  "judgement",
                  "failure_reasons",
                  "Tumor_Sample_Barcode",
                  "dbSNP_Val_Status",
                  "dbSNP_RS",
                  "X1000gp3_AF",
                  "X1000gp3_AMR_AF",
                  "X1000gp3_AFR_AF",
                  "X1000gp3_EUR_AF",
                  "X1000gp3_EAS_AF",
                  "X1000gp3_SAS_AF",
                  "COSMIC_overlapping_mutations"
)

###############################
#         Functions           #
###############################


# Function to filter mutations with strand bias (LOD fwd / LOD rev >= |5|)
strand_bias_function <- function(all_tDNA_maf){
  filtered_ctDNA_maf <- all_ctDNA_maf[all_ctDNA_maf$skew1 < LODfwd_rev_ratio_thr,]
  filtered_ctDNA_maf <- filtered_ctDNA_maf[filtered_ctDNA_maf$skew1 >= 0,]
  filtered_ctDNA_maf <- filtered_ctDNA_maf[filtered_ctDNA_maf$skew2 < LODfwd_rev_ratio_thr,]
  filtered_ctDNA_maf <- filtered_ctDNA_maf[filtered_ctDNA_maf$skew2 >= 0,]
  filtered_ctDNA_maf <- filtered_ctDNA_maf[complete.cases(filtered_ctDNA_maf$Start_position),]
  #removes NA data
  return(filtered_ctDNA_maf)
}
strand_bias_function_rm <- function(all_ctDNA_maf){
  removed_ctDNA_maf_1 <- all_ctDNA_maf[all_ctDNA_maf$skew1 >= LODfwd_rev_ratio_thr,]
  removed_ctDNA_maf_2 <- all_ctDNA_maf[all_ctDNA_maf$skew1 < 0,]
  removed_ctDNA_maf_3 <- all_ctDNA_maf[all_ctDNA_maf$skew2 >= LODfwd_rev_ratio_thr,]
  removed_ctDNA_maf_4 <- all_ctDNA_maf[all_ctDNA_maf$skew2 < 0,]
  removed_ctDNA_maf_strand_bias <- rbind(removed_ctDNA_maf_1, removed_ctDNA_maf_2, removed_ctDNA_maf_3, 
                                         removed_ctDNA_maf_4)
  removed_ctDNA_maf_strand_bias <- unique(removed_ctDNA_maf_strand_bias)
  return(removed_ctDNA_maf_strand_bias)
}

# Function for removing germline SNPs based on 1000Genomes Project allele frequency in specific ethnic populations
ctDNA_filter_SNP_eth <- function(filtered_ctDNA_maf){
  SNP_maf1 <- subset(filtered_ctDNA_maf, as.numeric(as.character(X1000gp3_AF)) >= X1000Gen_thresh)
  SNP_maf2 <- subset(filtered_ctDNA_maf, as.numeric(as.character(X1000gp3_AFR_AF)) >= X1000Gen_thresh)
  SNP_maf3  <- subset(filtered_ctDNA_maf, as.numeric(as.character(X1000gp3_AMR_AF)) >= X1000Gen_thresh)
  SNP_maf4  <- subset(filtered_ctDNA_maf, as.numeric(as.character(X1000gp3_EUR_AF)) >= X1000Gen_thresh)
  SNP_maf5  <- subset(filtered_ctDNA_maf, as.numeric(as.character(X1000gp3_EAS_AF)) >= X1000Gen_thresh)
  SNP_maf6  <- subset(filtered_ctDNA_maf, as.numeric(as.character(X1000gp3_SAS_AF)) >= X1000Gen_thresh)
  ethnic_SNP_maf <- rbind(SNP_maf1,SNP_maf2,SNP_maf3,SNP_maf4,SNP_maf5,SNP_maf6)
  ethnic_SNP_maf <- unique(ethnic_SNP_maf)
  return(ethnic_SNP_maf)
}


###############################
#           Main
###############################

# Combine all maf files from ctDNA data directory into one file and while converting tumor LOD scores
# (generated by MuTect) into modified Z-scores (represented as the number of median absolute deviations from  
# the median) using the distribution of LOD scores within each sample

filenames <- list.files(path = file.path, pattern = file.ext,
                        full.names = T, recursive = FALSE,
                        ignore.case = FALSE, include.dirs = FALSE)
all_ctDNA_maf <- NULL
all_pop_data <- NULL      

for (file in filenames){
  ctDNA_maf <- read.table(file, header = TRUE, sep = "\t", quote = "",
                          comment.char = "#", stringsAsFactors =FALSE)
  ## remove all calls REJECTED by MuTect as likely sequencer errors
  ## (only needed if REJECT mutations were included in the MuTect output file)
  ctDNA_maf <- ctDNA_maf[ctDNA_maf$judgement == "KEEP",]
  ## remove mutation calls made using a small fraction of total reads
  ctDNA_maf$total_supp_reads <- ctDNA_maf$t_alt_count + ctDNA_maf$t_ref_count
  ctDNA_maf$fraction_supp_reads <- ctDNA_maf$total_supp_reads / ctDNA_maf$total_pairs
  ctDNA_maf <- ctDNA_maf[ctDNA_maf$fraction_supp_reads > Fraction_supp_reads,]
  ## simplify sample name to study subject ID (MYL-XXX)
  name <- basename(file)
  name <- gsub(".call_stats.maf","",name)
  name <- gsub(".bam","",name)  
  name <- gsub(".processed","",name)
  ctDNA_maf$row_names <- paste(name,ctDNA_maf$Genome_Change,sep="_")
  ctDNA_maf$Sample_ID <- paste(name)
  ## Convert tumor LOD scores to modified Z-scores, i.e., the number of Median Absolute Deviations (MADs)
  ## from the median LOD score in each sample
  LOD_scores <- ctDNA_maf$t_lod_fstar
  median_LOD <- as.numeric(median(LOD_scores))
  MAD_LOD  <- as.numeric(mad(LOD_scores))
  LOD_threshold <- as.numeric(median_LOD + LOD_Zscore_thresh*MAD_LOD)
  # Convert tomor LOD scores to Modified Z-scores using sample-specific distribution of LODs (median, MAD)
  ctDNA_maf$modified_Z_score <- (ctDNA_maf$t_lod_fstar - median_LOD)/MAD_LOD
  total_mut <- as.numeric(nrow(ctDNA_maf))
  pop_data <- c(name, total_mut, median_LOD, MAD_LOD, LOD_threshold)
  all_pop_data <- rbind(all_pop_data, pop_data)
  all_ctDNA_maf <- rbind(all_ctDNA_maf, ctDNA_maf) 
}

###############################################################
##  Filtering of sequencing artifacts and polymerase errors  ##
###############################################################

# STEP 1: Prepare a summary table showing the statistical values for the distribution of LOD scores within each sample
colnames(all_pop_data) <- paste(c("sample_ID", "Total_Mutations", "Median_LOD", "MAD", "LOD_Threshold"))
write.table(all_pop_data, file = paste("LOD_score_distribution",projectname,"txt",sep="."),
            row.names=FALSE, append = FALSE,na = "NA", quote = FALSE, sep = "\t", col.names = TRUE)

# STEP 2: Add additional columns in the dataframe required for downstream filtering
all_ctDNA_maf$skew1 <- all_ctDNA_maf$t_lod_fstar_forward / all_ctDNA_maf$t_lod_fstar_reverse
all_ctDNA_maf$skew2 <- all_ctDNA_maf$t_lod_fstar_reverse / all_ctDNA_maf$t_lod_fstar_forward

# STEP 3: Remove mutations with strand bias (calls with X-fold difference between Forward and Reverse t_lod_fstar)
removed_ctDNA_maf_strand_bias <- strand_bias_function_rm(all_ctDNA_maf)
filtered_ctDNA_maf <- strand_bias_function(all_ctDNA_maf)
count_filtered_maf_1 <- nrow(filtered_ctDNA_maf)
count_removed_strand_bias <- nrow(removed_ctDNA_maf_strand_bias)

# STEP 4: Apply LOD score filter: keep only the mutations with t_lod_fstar >= THRESHOLD
removed_ctDNA_maf_LOD <- filtered_ctDNA_maf[filtered_ctDNA_maf$modified_Z_score < LOD_Zscore_thresh,]
filtered_ctDNA_maf <- filtered_ctDNA_maf[filtered_ctDNA_maf$modified_Z_score >= LOD_Zscore_thresh,]
count_filtered_maf_2 <- nrow(filtered_ctDNA_maf)
count_removed_LOD_thr <- nrow(removed_ctDNA_maf_LOD)

# Make a summary table of all real mutation calls (germline SNPs + somatic variants)
filtered_summary_maf <- filtered_ctDNA_maf[,summary_vect]
write.table(filtered_summary_maf, file = paste("SNP_and_somatic_combined",projectname,"txt",sep="."),
row.names=FALSE, append = FALSE, na = "NA", quote = FALSE, sep = "\t", col.names = TRUE)


###############################################################
##  Optional removal of germline SNPs using population data  ##
###############################################################

# Filtering validated germline SNPs using Oncotator version 1.5.3.0 annotation data
removed_ctDNA_maf_valSNP <- filtered_ctDNA_maf[!filtered_ctDNA_maf$dbSNP_Val_Status == "",]
removed_ctDNA_maf_valSNP <- subset(filtered_ctDNA_maf, as.numeric(as.character(X1000gp3_AF)) >= X1000Gen_thresh)
val_SNPs_list <- removed_ctDNA_maf_valSNP$Genome_Change
filtered_ctDNA_maf <- subset(filtered_ctDNA_maf, !(Genome_Change %in% val_SNPs_list))

# Filtering additional SNPs with 1000 Genomes data AF >= X1000Gen_thresh in specific ethnic groups
ethnic_SNP_maf <- ctDNA_filter_SNP_eth(filtered_ctDNA_maf)
ethnic_SNPs <- ethnic_SNP_maf$Genome_Change 
filtered_ctDNA_maf <- subset(filtered_ctDNA_maf, !(Genome_Change %in% ethnic_SNPs))
count_filtered_maf_3 <- nrow(filtered_ctDNA_maf)
SNP_maf <- rbind(removed_ctDNA_maf_valSNP, ethnic_SNP_maf)
count_removed_SNPs <- nrow(SNP_maf)

# Prepare a table summarizing all germline SNPs and related data
SNP_summary_maf <- SNP_maf[,summary_vect]
write.table(SNP_summary_maf, file = paste("SNPs_summary",projectname,"txt",sep="."),
row.names=FALSE, append = FALSE, na = "NA", quote = FALSE, sep = "\t", col.names = TRUE)


####################################
##  Generate Data Summary Tables  ##
####################################

# Create filtering data summary
filter_type    <- c("pre-filtering","Strand Bias (LOD fwd/rev rario)",
                    "Below LOD Threshold", "mutations identified as germline SNPs")
removed_count  <- c(0, count_removed_strand_bias,
                    count_removed_LOD_thr, count_removed_SNPs)
remaining_count <- c(nrow(all_ctDNA_maf), count_filtered_maf_1,
                     count_filtered_maf_2, count_filtered_maf_3)
filtering_summary <- data.frame(filter_type, removed_count, remaining_count)

write.table(filtering_summary, file = paste("Filtering_summary",projectname,"txt",sep="."),
row.names=FALSE, append = FALSE, na = "NA", quote = FALSE, sep = "\t", col.names = TRUE)

# prepare summaries of all mutation calls and filtered somatic calls and write into tables
filtered_summary_maf <- filtered_ctDNA_maf[,summary_vect]
write.table(filtered_summary_maf, file = paste("Somatic_summary",projectname,"txt",sep="."),
            row.names=FALSE, append = FALSE, na = "NA", quote = FALSE, sep = "\t", col.names = TRUE)
