# scRNAseq analysis on ALCL, Thymus, and RLN datasets pipeline documentation

# Load required libraries
library(Seurat)
library(pheatmap)
library(ggrepel)
library(ggplot2)
library(dplyr)
library(tidyr)
library(readxl)



# Data import (all samples available)
set.seed(123)

setwd('~/scRNAseq_ALCL_Thymus_RLN')

lib.info <- readxl::read_xlsx('metadata/lib_ALCL_Thymus_RLN.xlsx')

#Create seurat object
sc.obj <- NULL

# Iterate over each row in lib.info to load data
for (i in 1:nrow(lib.info)) {
    i.df <- lib.info[i,]
    i.dir <- paste0(i.df$AnalysisDir)  # Get dataset path
    i.data <- Read10X(data.dir = i.dir)  # Read 10X data
    i.obj <- CreateSeuratObject(counts = i.data, project = i.df$Sample)  # Create Seurat object
    i.obj <- RenameCells(i.obj, add.cell.id = i.df$Sample)  # Rename cells with sample ID
    
    # Merge Seurat objects dynamically
    if (is.null(sc.obj)) {
        sc.obj <- i.obj
    } else {
        sc.obj <- merge(sc.obj, i.obj)
    }
}

# Add metadata annotations
lib.info <- lib.info %>% select(Sample, StudyID) # Only keep necessary columns
sc.obj@meta.data <- sc.obj@meta.data %>%
    mutate(
        Sample = orig.ident  # Ensure `orig.ident` matches Sample names
    ) %>%
    left_join(lib.info, by = "Sample")  # Merge metadata based on Sample ID

#Assign Correct Cell Names
rownames(sc.obj@meta.data) <- Cells(sc.obj)
colnames(sc.obj) <- Cells(sc.obj)


#QC
meta <- sc.obj@meta.data

# add mt%
sc.obj[["percent.mt"]] <- PercentageFeatureSet(sc.obj, pattern = "^MT-")
sc.obj[["percent.rb"]] <- PercentageFeatureSet(sc.obj, pattern = "^RP[LS]")

# These figures will give you a brief overview of the qualities
# check the distribution of nfeature(number of expressed genes), ncount(number of RNA molecues) and mt percent
png(filename = paste0('plots/250602_vlnplot_QC_allsample.png'), width = 1500, height = 600)
print(VlnPlot(sc.obj, features = c("nFeature_RNA", "nCount_RNA", "percent.mt"), ncol = 3, group.by = 'StudyID',raster=FALSE))
dev.off()
# warning message: Warning: Default search for "data" layer in "RNA" assay yielded no results; utilizing "counts" layer instead.
# This just means that the Seurat object doesn’t have a "data" slot (log-normalized data), and VlnPlot is using the "counts" slot (raw UMI counts) instead.

# how to resolve, then rerun the violin plot 
# sc.obj <- NormalizeData(sc.obj)

#filtering high mt
keep.mito <- sc.obj$percent.mt < 20  # keep cells with mt% < 20%

# in this step, we use 4*MAD to filter outlier cells
keep.nGene <- rep(NA, ncol(sc.obj))
for (s in unique(sc.obj$orig.ident)) {
	s.idx <- which(sc.obj$orig.ident == s)
	s.median <- median(sc.obj$nFeature_RNA[s.idx])
	s.mad <- mad(sc.obj$nFeature_RNA[s.idx])
	s.keep.nGene <- (sc.obj$nFeature_RNA[s.idx] <= s.median + (4 * s.mad)) & (sc.obj$nFeature_RNA[s.idx] >= s.median - (4 * s.mad))
	keep.nGene[s.idx] <- s.keep.nGene
}

# Create some QC plots
qc.df <- sc.obj@meta.data
qc.df <- cbind(qc.df, keep_nGene = keep.nGene, keep_mito = keep.mito, keep = keep.mito & keep.nGene)

png(paste0("plots/250623_barPlot_before_after_qc_allsample.png"), width = 1200, height = 900)
print(
  ggplot(qc.df, aes(x = StudyID, fill = keep)) +
    geom_bar(stat = "count", position = "dodge") +
    scale_fill_manual(values = c("TRUE" = "black", "FALSE" = "red")) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1, size = 20),
          axis.text.y = element_text(size = 20),
          axis.title.y = element_text(size = 24),
          legend.title = element_text(size = 24),
          legend.text = element_text(size = 20)) +
    labs(x = '', y = 'Number of Cells')
)
dev.off()

# This will:
# Color high-quality cells (keep = TRUE) as black
# Color filtered-out cells (keep = FALSE) as red

# Save filtered seurat object
saveRDS(sc.obj, "data/250623_merged_scobj_qc_preprocessed.rds")

# last updated: 2025-02-06
