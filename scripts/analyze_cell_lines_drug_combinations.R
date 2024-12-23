library(data.table)
library(ggplot2)
library(gplots)
library(ComplexHeatmap)
library(BiocManager)
library(GSVA)
library(BiocParallel)
library(doParallel)
library(stringr)
library(circlize)
library(RColorBrewer)
library(ggpubr)
library(stringr)
library(GSA)
library(Matrix)
library(extrafont)
library(Rtsne)
library(immunedeconv)
library(Polychrome)
library(R.utils)
library(igraph)
library(dnet)
library(AUCell)
loadfonts()
registerDoParallel(20)
ht_opt$message = FALSE

setwd("/home/raghvendra/TII/Projects/Raghav/Immunoinformatics/")
source("scripts/all_cells_functions.R")

#Load the file with the drug-cell line combinations
################################################################################
cell_drug_df <- fread("BeatAML/Data/beataml_probit_curve_fits_v4_dbgap.txt",header=T)
cell_drug_df <- as.data.frame(cell_drug_df)

#Get the drug and their target information
################################################################################
drug_targets_df <- fread("Results/target_gene_info.csv",header=T)
drug_targets_df <- as.data.frame(drug_targets_df)

#Get the list of unique drugs and see if all the drugs are in the drug target file
################################################################################
unique_drugs <- unique(cell_drug_df$inhibitor)
sum(unique_drugs %in% drug_targets_df$Name)

#Get the unique cell lines
################################################################################
unique_cell_lines <- unique(cell_drug_df$dbgap_rnaseq_sample)

#Load the training and test sample ids
################################################################################
load("Data/Train_Test_Ids.Rdata")
rev_train_ids <- train_sample_ids[train_sample_ids %in% unique_cell_lines]
rev_test_ids <- test_sample_ids[test_sample_ids %in% unique_cell_lines]
save(rev_train_ids,rev_test_ids,file="Data/Revised_Train_Test_Ids.Rdata")

#Get the cell line, drug combo for only those cell lines which are part of train and test set
################################################################################
train_cell_drug_df <- cell_drug_df[cell_drug_df$dbgap_rnaseq_sample %in% rev_train_ids,]
test_cell_drug_df <- cell_drug_df[cell_drug_df$dbgap_rnaseq_sample %in% rev_test_ids,]

#Join the drug targets df with cell line, drug combination df
################################################################################
revised_drug_targets_df <- drug_targets_df[,c("CID","MolecularWeight","CanonicalSMILES","InChIKey","XLogP","Name")]
colnames(revised_drug_targets_df)[6] <- "inhibitor"
rev_train_cell_drug_df <- merge(train_cell_drug_df, revised_drug_targets_df, by="inhibitor", all=F)
rev_test_cell_drug_df <- merge(test_cell_drug_df, revised_drug_targets_df, by="inhibitor", all=F)
rev_train_cell_drug_df <- rev_train_cell_drug_df[complete.cases(rev_train_cell_drug_df),]
rev_test_cell_drug_df <- rev_test_cell_drug_df[complete.cases(rev_test_cell_drug_df),]

#Load the training/test data with clinical information
################################################################################
train_cell_line_part1_df <- fread("Data/Training_Set_with_Expr_Clin_PA_CTS_P1.csv.gz",header=T,quote="",sep="\t")
train_cell_line_part2_df <- fread("Data/Training_Set_with_Expr_Clin_PA_CTS_P2.csv.gz",header=T,quote="",sep="\t")
test_cell_line_df <- fread("Data/Test_Set_with_Expr_Clin_PA_CTS.csv.gz",header=T,quote="",sep="\t")
train_onco_cell_line_df <- fread("Data/Training_Set_with_Onco_Var_Expr_Clin_PA_CTS.csv",header=T,quote="",sep="\t")
test_onco_cell_line_df <- fread("Data/Test_Set_with_Onco_Var_Expr_Clin_PA_CTS.csv",header=T,quote="",sep="\t")
train_cell_line_part1_df <- as.data.frame(train_cell_line_part1_df)
train_cell_line_part2_df <- as.data.frame(train_cell_line_part2_df)
test_cell_line_df <- as.data.frame(test_cell_line_df)
train_onco_cell_line_df <- as.data.frame(train_onco_cell_line_df)
test_onco_cell_line_df <- as.data.frame(test_onco_cell_line_df)
rev_train_cell_line_part1_df <- train_cell_line_part1_df[train_cell_line_part1_df$dbgap_rnaseq_sample %in% rev_train_ids,]
rev_train_cell_line_part2_df <- train_cell_line_part2_df[train_cell_line_part2_df$dbgap_rnaseq_sample %in% rev_train_ids,]
rev_test_cell_line_df <- test_cell_line_df[test_cell_line_df$dbgap_rnaseq_sample %in% rev_test_ids,]
rev_train_onco_cell_line_df <- train_onco_cell_line_df[train_onco_cell_line_df$dbgap_rnaseq_sample %in% rev_train_ids,]
rev_test_onco_cell_line_df <- test_onco_cell_line_df[test_onco_cell_line_df$dbgap_rnaseq_sample %in% rev_test_ids,]

#Make the t-sne plot of the dataset using all cell line features (oncogenes + clinical + pathway + modules + mutations)
################################################################################
set.seed(123)
rev_cell_line_df <- as.data.frame(rbind(rev_train_onco_cell_line_df, rev_test_onco_cell_line_df))
final_rev_cell_line_df <- rev_cell_line_df[,c(2:794,795,796,813,837,858,859,862:868,870:873,875,876,881,884,892:965)]

#Remove columns with NA or characters
na_col_ids <- which(colSums(is.na(final_rev_cell_line_df))>0)
str_col_ids <- which(sapply(final_rev_cell_line_df,class)=="character")
last_rev_cell_line_df <- final_rev_cell_line_df[,-union(na_col_ids,str_col_ids)]

#Make t-sne plot of the cell line features as Supp Fig 1A
final_tsne_out <- Rtsne(X=last_rev_cell_line_df, dims=2, perplexity = 30.0, pca_center = T, pca_scale = T, pca = T)
final_tsne_df <- as.data.frame(final_tsne_out[["Y"]])
colnames(final_tsne_df) <- c("Tsne1","Tsne2")
final_tsne_df$Pheno <- rev_cell_line_df$Pheno
unique_phenotypes <- unique(final_tsne_df$Pheno)
final_tsne_df$Pheno <- factor(final_tsne_df$Pheno, levels = unique_phenotypes)

P28 = createPalette(28,  c("#ff0000", "#00ff00", "#0000ff"))
palette(P28)
g_tsne <- ggplot(data=final_tsne_df, aes(x=Tsne1, y=Tsne2, color=Pheno)) + geom_point(aes(color=Pheno), size=2) + theme_bw() + xlab("T-SNE Dim1") + ylab("T-SNE Dim2") +
  theme(legend.title.align=0.0, legend.text.align = 0.0) +
  theme(axis.text.x = element_text(color = "grey20", size = 16, angle = 0, hjust = .5, vjust = .5, face = "plain"),
        strip.text = element_text(color = "white", size=20, angle=0, hjust = 0.5, vjust = 0.5, face = "plain"),
        axis.text.y = element_text(color = "grey20", size = 16, angle = 0, hjust = 1, vjust = 0, face = "plain"),
        axis.title.x = element_text(color = "grey20", size = 20, angle = 0, hjust = .5, vjust = 0, face = "plain"),
        axis.title.y = element_text(color = "grey20", size = 20, angle = 90, hjust = .5, vjust = .5, face = "plain"),
        legend.text = element_text(color="grey20", size=18, angle = 0, face="plain"),
        title=element_text(color="grey20", size=20, face="plain"))
ggsave(filename=paste0("Results/Feature_Set_T-SNE_plot.pdf"), plot = g_tsne, device = pdf(), height = 8, width=8, units="in")
dev.off()


#Write out all these revised files
###############################################################################
write.table(rev_train_cell_line_part1_df,file="Data/Revised_Training_Set_with_Expr_Clin_PA_CTS_P1.csv",row.names=F, col.names=T, quote=F,sep="\t")
write.table(rev_train_cell_line_part2_df,file="Data/Revised_Training_Set_with_Expr_Clin_PA_CTS_P2.csv",row.names=F, col.names=T, quote=F,sep="\t")
write.table(rev_test_cell_line_df,file="Data/Revised_Test_Set_with_Expr_Clin_PA_CTS.csv",row.names=F,col.names=T,quote=F,sep="\t")
write.table(rev_train_onco_cell_line_df,file="Data/Revised_Training_Set_with_Onco_Var_Expr_Clin_PA_CTS.csv",row.names=F, col.names=T, quote=F,sep="\t")
write.table(rev_test_onco_cell_line_df,file="Data/Revised_Test_Set_with_Onco_Var_Expr_Clin_PA_CTS.csv",row.names=F, col.names=T, quote=F,sep="\t")

final_train_cell_line_df <- as.data.frame(rbind(rev_train_cell_line_part1_df, rev_train_cell_line_part2_df))

#Load the string ppi matrix as an adjacency matrix
################################################################################
string_ppi_df <- read.table("Data/String_PPI_Cutoff_0.7.csv",header=T)
g_ppi <- graph_from_edgelist(as.matrix(string_ppi_df[,c(1:2)]), directed = T)
E(g_ppi)$weight <- string_ppi_df$combined_score
N_ppi <- length(V(g_ppi))

#Get the data frame of each drug and the affinity to all proteins from their target genes
################################################################################
p0_matrix <- matrix(0, nrow=N_ppi, ncol=length(unique_drugs))
rownames(p0_matrix) <- V(g_ppi)$name
for (i in 1:length(unique_drugs))
{
  drug_name <- unique_drugs[i]
  targets <- drug_targets_df[drug_targets_df$Name==drug_name,]$Targets
  targets <- unlist(strsplit(targets,split=";"))
  p0_vec <- rep(0, N_ppi)
  names(p0_vec) <- V(g_ppi)$name
  p0_vec[names(p0_vec) %in% targets] <- 1
  p0_matrix[,i] <- p0_vec
}
#This is the random walk with restart distance of all genes from target genes of a drug
pinf_matrix <- sqrt(dRWR(g = g_ppi, normalise = "laplacian", setSeeds = p0_matrix, restart = 0.5, multicores = 8))
rownames(pinf_matrix) <- V(g_ppi)$name
colnames(pinf_matrix) <- unique_drugs
pinf_matrix <- as.matrix(pinf_matrix)

#Build the drug affinity and cell line expression combination matrix
################################################################################
all_genes_in_ppi <- rownames(pinf_matrix)
all_genes_in_cell_line <- colnames(final_train_cell_line_df)[c(2:22844)]
common_genes <- intersect(all_genes_in_ppi, all_genes_in_cell_line)

#Get the stationary affinity matrix from the drugs for all common set of genes
revised_pinf_matrix <- t(pinf_matrix[common_genes,])

#Get the expression of common set of genes
revised_train_cell_line_expr_df <- final_train_cell_line_df[,common_genes]
rownames(revised_train_cell_line_expr_df) <- final_train_cell_line_df$dbgap_rnaseq_sample
revised_test_cell_line_expr_df <- rev_test_cell_line_df[,common_genes]
rownames(revised_test_cell_line_expr_df) <- rev_test_cell_line_df$dbgap_rnaseq_sample

#Get drug, cell line specific affinity/distance measures for training set taking expression level of a gene in a cell line into account
################################################################################
drug_cell_affinity_combinations <- t(sapply(1:length(common_genes), function(i) tcrossprod(revised_pinf_matrix[,i ], revised_train_cell_line_expr_df[,i ])))
drug_cell_affinity_combinations_mat <- Matrix(drug_cell_affinity_combinations, sparse=T)
rm(drug_cell_affinity_combinations)
gc()

#Get the column names for all the data as well as gene names
all_drug_cell_line_combination <- as.data.frame(expand.grid(rownames(revised_pinf_matrix),rownames(revised_train_cell_line_expr_df)))
all_drug_cell_line_combination <- paste0(all_drug_cell_line_combination$Var1,"_",all_drug_cell_line_combination$Var2) 
colnames(drug_cell_affinity_combinations_mat) <- all_drug_cell_line_combination 
rownames(drug_cell_affinity_combinations_mat) <- common_genes

#Build the cell rankings using AUcell method on the drug-cell line distance information
################################################################################
load("Data/Selected.pathways.3.4.RData")
blocks = 50
N = ncol(drug_cell_affinity_combinations_mat)
blocksize = ceiling(N/50)
auc_scores_df <- NULL
for (i in 1:50)
{
  if (i!=50)
  {
    ids <- c(((i-1)*blocksize+1):(i*blocksize))
  }else{
    ids <- c(((i-1)*blocksize+1):(N))
  }
  cell_rankings_temp <- AUCell_buildRankings(exprMat = as.matrix(drug_cell_affinity_combinations_mat[,ids]), nCores = 8, plotStats = T)
  temp_auc_scores <- AUCell_calcAUC(geneSets = Selected.pathways, rankings = cell_rankings_temp, nCores = 8, normAUC = T, aucMaxRank = ceiling(0.5*nrow(cell_rankings_temp)))
  auc_scores_df <- AUCell::cbind(auc_scores_df, temp_auc_scores@assays@data@listData$AUC)
  rm(temp_auc_scores)
  rm(cell_rankings_temp)
  gc()
}
auc_scores_df <- t(auc_scores_df)
colnames(auc_scores_df) <- paste0("AUC_",names(Selected.pathways))

#Drug - Cell Line combinations to keep
combinations_to_keep <- paste0(cell_drug_df$inhibitor,"_",cell_drug_df$dbgap_rnaseq_sample)
cell_drug_df$primary_key <- combinations_to_keep

#Have the primary key
subset_auc_scores_df <- auc_scores_df[rownames(auc_scores_df) %in% combinations_to_keep,]
for (i in 1:ncol(subset_auc_scores_df))
{
  subset_auc_scores_df[,i] <- signif(subset_auc_scores_df[,i],digits=3)
}
subset_auc_scores_df <- as.data.frame(subset_auc_scores_df)
subset_auc_scores_df$primary_key <- rownames(subset_auc_scores_df)

train_cell_drug_df <- merge(cell_drug_df,subset_auc_scores_df,on="primary_key",all=F)
write.table(train_cell_drug_df, file="Data/Revised_Training_Set_with_IC50.csv",row.names=F,col.names=T,quote=F,sep="\t")


#Get drug, cell line specific affinity/distance measures for test set taking expression level of a gene in a cell line into account
################################################################################
drug_cell_affinity_combinations <- t(sapply(1:length(common_genes), function(i) tcrossprod(revised_pinf_matrix[,i ], revised_test_cell_line_expr_df[,i ])))
drug_cell_affinity_combinations_mat <- Matrix(drug_cell_affinity_combinations, sparse=T)
rm(drug_cell_affinity_combinations)
gc()

#Get the column names for all the data as well as gene names
all_drug_cell_line_combination <- as.data.frame(expand.grid(rownames(revised_pinf_matrix),rownames(revised_test_cell_line_expr_df)))
all_drug_cell_line_combination <- paste0(all_drug_cell_line_combination$Var1,"_",all_drug_cell_line_combination$Var2) 
colnames(drug_cell_affinity_combinations_mat) <- all_drug_cell_line_combination 
rownames(drug_cell_affinity_combinations_mat) <- common_genes

#Build the cell rankings using AUcell method on the drug-cell line distance information
################################################################################
blocks = 50
N = ncol(drug_cell_affinity_combinations_mat)
blocksize = ceiling(N/50)
auc_scores_df <- NULL
for (i in 1:50)
{
  if (i!=50)
  {
    ids <- c(((i-1)*blocksize+1):(i*blocksize))
  }else{
    ids <- c(((i-1)*blocksize+1):(N))
  }
  cell_rankings_temp <- AUCell_buildRankings(exprMat = as.matrix(drug_cell_affinity_combinations_mat[,ids]), nCores = 8, plotStats = T)
  temp_auc_scores <- AUCell_calcAUC(geneSets = Selected.pathways, rankings = cell_rankings_temp, nCores = 8, normAUC = T, aucMaxRank = ceiling(0.5*nrow(cell_rankings_temp)))
  auc_scores_df <- AUCell::cbind(auc_scores_df, temp_auc_scores@assays@data@listData$AUC)
  rm(temp_auc_scores)
  rm(cell_rankings_temp)
  gc()
}
auc_scores_df <- t(auc_scores_df)
colnames(auc_scores_df) <- paste0("AUC_",names(Selected.pathways))

#Drug - Cell Line combinations to keep
combinations_to_keep <- paste0(cell_drug_df$inhibitor,"_",cell_drug_df$dbgap_rnaseq_sample)
cell_drug_df$primary_key <- combinations_to_keep

#Have the primary key
subset_auc_scores_df <- auc_scores_df[rownames(auc_scores_df) %in% combinations_to_keep,]
for (i in 1:ncol(subset_auc_scores_df))
{
  subset_auc_scores_df[,i] <- signif(subset_auc_scores_df[,i],digits=3)
}
subset_auc_scores_df <- as.data.frame(subset_auc_scores_df)
subset_auc_scores_df$primary_key <- rownames(subset_auc_scores_df)

test_cell_drug_df <- merge(cell_drug_df,subset_auc_scores_df,on="primary_key",all=F)
write.table(test_cell_drug_df, file="Data/Revised_Test_Set_with_IC50.csv",row.names=F,col.names=T,quote=F,sep="\t")
