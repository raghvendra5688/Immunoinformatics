# ---
# jupyter:
#   jupytext:
#     formats: ipynb,py:light
#     text_representation:
#       extension: .py
#       format_name: light
#       format_version: '1.5'
#       jupytext_version: 1.14.5
#   kernelspec:
#     display_name: Python 3 (ipykernel)
#     language: python
#     name: python3
# ---

# +
import os
import pickle
import re
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sn
import numpy as np
import re 

import xgboost as xgb
import lightgbm
import catboost
from sklearn import ensemble
from sklearn import dummy
from sklearn import linear_model
from sklearn import svm
from sklearn import neural_network
from sklearn import metrics
from sklearn import preprocessing
from sklearn.pipeline import make_pipeline
from sklearn.model_selection import train_test_split
from sklearn.utils.fixes import loguniform
import scipy
import argparse

from misc import save_model, load_model, regression_results, grid_search_cv, calculate_regression_metrics, supervised_learning_steps, get_CV_results
# -
#Get the setting with different X_trains and X_tests
train_options = ["../Data/Training_Set_Var_with_Drug_Embedding_Cell_Info.pkl",
                 "../Data/Training_Set_Var_with_Drug_MFP_Cell_Info.pkl",
                 ".."]
test_options = ["../Data/Test_Set_Var_with_Drug_Embedding_Cell_Info.pkl",
                "../Data/Test_Set_Var_with_Drug_MFP_Cell_Info.pkl",
                ".."]
data_type_options = ["LS_Feat_Var","MFP_Feat_Var"]


# +
#Choose the options
input_option = 1                                                  #Choose 0 for LS for Drug and LS for Cell Line , 1 for MFP for Drug and LS for Cell Line 
classification_task = False
data_type = data_type_options[input_option]

#Get the data for your choice: LS or MFP
print("Loaded training file")
big_train_df = pd.read_pickle(train_options[input_option],compression="zip")
big_test_df = pd.read_pickle(test_options[input_option],compression="zip")
big_train_df = big_train_df.rename(columns = lambda x:re.sub('[^A-Za-z0-9_]+', '', x))
big_test_df = big_test_df.rename(columns = lambda x:re.sub('[^A-Za-z0-9_]+', '', x))
total_length = len(big_train_df.columns)
if (input_option==0):
    #Consider only those columns which have numeric values
    metadata_X_train,X_train, Y_train = big_train_df.loc[:,["dbgap_rnaseq_sample","inhibitor"]], big_train_df.iloc[:,[1,4]+[*range(6,262,1)]+[*range(288,total_length,1)]], big_train_df["auc"].to_numpy().flatten()
    metadata_X_test,X_test, Y_test = big_test_df.loc[:,["dbgap_rnaseq_sample","inhibitor"]], big_test_df.iloc[:,[1,4]+[*range(6,262,1)]+[*range(288,total_length,1)]], big_test_df["auc"].to_numpy().flatten()
elif (input_option==1):
    metadata_X_train,X_train, Y_train = big_train_df.loc[:,["dbgap_rnaseq_sample","inhibitor"]], big_train_df.iloc[:,[1,4]+[*range(6,1030,1)]+[*range(1056,total_length,1)]], big_train_df["auc"].to_numpy().flatten()
    metadata_X_test,X_test, Y_test = big_test_df.loc[:,["dbgap_rnaseq_sample","inhibitor"]], big_test_df.iloc[:,[1,4]+[*range(6,1030,1)]+[*range(1056,total_length,1)]], big_test_df["auc"].to_numpy().flatten()

#Keep only numeric training and test set and those which have no Nans
X_train_numerics_only = X_train.select_dtypes(include=np.number)
X_test_numerics_only = X_test[X_train_numerics_only.columns]
print("Shape of training set after removing non-numeric cols")
print(X_train_numerics_only.shape)
print(X_test_numerics_only.shape)


nan_cols = [i for i in X_train_numerics_only.columns if X_train_numerics_only[i].isnull().any()]
rev_X_train = X_train_numerics_only.drop(nan_cols,axis=1)
rev_X_test = X_test_numerics_only.drop(nan_cols,axis=1)
print("Shape of training set after removing cols with NaNs")
print(rev_X_train.shape)
print(rev_X_test.shape)
# +
all_columns = rev_X_train.columns.tolist()
drug_columns = range(0,1026)
auc_columns = range(1026,1080)
var_onco_columns = range(1080,1873)
clinical_columns = range(1873,1876)
pathway_columns = range(1876,1930)
module_columns = range(1930,1950)
mutation_columns = range(1950,2333)

data_types = ["MFP_AUC","MFP_AUC_Onco_Var","MFP_AUC_Pathways","MFP_AUC_Module","MFP_AUC_Mutation",
            "MFP_AUC_Onco_Var_Pathways","MFP_AUC_Onco_Var_Module","MFP_AUC_Onco_Var_Mutation",
            "MFP_AUC_Pathways_Module","MFP_AUC_Pathways_Mutation","MFP_AUC_Module_Mutation",
            "MFP_AUC_Onco_Var_Pathways_Module","MFP_AUC_Onco_Var_Pathways_Mutation",
            "MFP_AUC_Onco_Var_Module_Mutation","MFP_AUC_Pathways_Module_Mutation"]

#Choose the ablation combination to study
ablation_option = 0
data_type = data_types[ablation_option]

#Make the list of column slices
default_columns = list(drug_columns)+list(auc_columns)+list(clinical_columns)
ablation_combinations = [default_columns, default_columns+list(var_onco_columns), default_columns+list(pathway_columns),
                        default_columns+list(module_columns),default_columns+list(mutation_columns),default_columns+list(var_onco_columns)+list(pathway_columns),
                        default_columns+list(var_onco_columns)+list(module_columns),default_columns+list(var_onco_columns)+list(mutation_columns),default_columns+list(pathway_columns)+list(module_columns),
                        default_columns+list(pathway_columns)+list(mutation_columns),default_columns+list(module_columns)+list(mutation_columns),
                        default_columns+list(var_onco_columns)+list(pathway_columns)+list(module_columns),default_columns+list(var_onco_columns)+list(pathway_columns)+list(mutation_columns),
                        default_columns+list(var_onco_columns)+list(module_columns)+list(mutation_columns),default_columns+list(pathway_columns)+list(module_columns)+list(mutation_columns)]

#Creat the final training and test set for MFP + AUC + combination accordingly
final_rev_X_train,final_rev_X_test = rev_X_train.iloc[:,ablation_combinations[ablation_option]],rev_X_test.iloc[:,ablation_combinations[ablation_option]]
print(final_rev_X_train.shape)
print(final_rev_X_test.shape)


# +
#Build the LightGBM Regression model
model = catboost.CatBoostRegressor(boosting_type="Plain",random_state=0, loss_function="MAE",thread_count=42)

# Grid parameters
params_catboost = {
    'iterations': [250,500,1000],
    'learning_rate':loguniform(1e-7,1),
    'depth': scipy.stats.randint(3, 10),
    'subsample': loguniform(0.8, 1e0),
    'colsample_bylevel': [0.1, 0.3, 0.5, 0.7, 0.9],
    'reg_lambda': loguniform(1,100)
}

        
#It will select 200 random combinations for the CV and do 5-fold CV for each combination
n_iter = 100
catboost_gs=supervised_learning_steps("catboost","r2",data_type,classification_task,model,params_catboost,final_rev_X_train,Y_train,n_iter=n_iter,n_splits=5)
        
#Build the model and get 5-fold CV results    
#print(catboost_gs.cv_results_)
# -

catboost_gs = load_model("catboost_models/catboost_"+data_type+"_regressor_gs.pk")
results = get_CV_results(catboost_gs,pd.DataFrame(rev_X_train),Y_train,n_splits=5)
print(results)

# +
#Test the linear regression model on separate test set  
catboost_gs = load_model("catboost_models/catboost_"+data_type+"_regressor_gs.pk")
np.max(catboost_gs.cv_results_["mean_test_score"])
catboost_best = catboost_gs.best_estimator_
y_pred_catboost=catboost_best.predict(rev_X_test)
test_metrics=calculate_regression_metrics(Y_test,y_pred_catboost)
print(test_metrics)

#Write the prediction of LR model
metadata_X_test['predictions']=y_pred_catboost
metadata_X_test['labels']=Y_test
metadata_X_test.to_csv("../Results/Catboost_"+data_type+"_supervised_test_predictions.csv",index=False,sep="\t")
print("Finished writing predictions")

fig = plt.figure()
plt.style.use('classic')
fig.set_size_inches(2.5,2.5)
fig.set_dpi(300)
fig.set_facecolor("white")

ax = sn.regplot(x="labels", y="predictions", data=metadata_X_test, scatter_kws={"color": "lightblue",'alpha':0.5}, 
                line_kws={"color": "red"})
title_text = "Catboost Prediction ("+data_type+")"
ax.axes.set_title(title_text,fontsize=6)
ax.set_xlim(0, 300)
ax.set_ylim(0, 300)
ax.set_xlabel("",fontsize=10)
ax.set_ylabel("",fontsize=10)
ax.tick_params(labelsize=10, color="black")
plt.text(25, 25, 'Pearson r =' +str(test_metrics[3]), fontsize = 10)
plt.text(25, 50, 'MAE ='+str(test_metrics[0]),fontsize=10)
outfilename = "../Results/Catboost_"+data_type+"_supervised_test_prediction.pdf"
plt.savefig(outfilename, bbox_inches="tight")

# +
#Get the most important variables and their feature importance scores
catboost_best = load_model("catboost_models/catboost_"+data_type+"_regressor_best_estimator.pk")
val, index = np.sort(catboost_best.feature_importances_), np.argsort(catboost_best.feature_importances_)
fig = plt.figure()
plt.style.use('classic')
fig.set_size_inches(4,3)
fig.set_dpi(300)
fig.set_facecolor("white")

ax = fig.add_subplot(111)
plt.bar(rev_X_train.columns[index[-20:]],val[-20:])
plt.xticks(rotation = 90) # Rotates X-Axis Ticks by 45-degrees

title_text = "Top Catboost VI ("+data_type+")"
ax.axes.set_title(title_text,fontsize=6)
ax.set_xlabel("Features",fontsize=9)
ax.set_ylabel("VI Value",fontsize=9)
ax.tick_params(labelsize=9)
outputfile = "../Results/Catboost_"+data_type+"_Coefficients.pdf"
plt.savefig(outputfile, bbox_inches="tight")
# -


