library(tidyverse)
library(lubridate)
library(zoo)
library(ggplot2)

#Create the ensemble model from all other forecasts
#Currently just the mean of the esimates and confidence intervals.
make_ensemble=function(all_forecasts, model_weights=NA, models_to_use=NA){
  ensemble = all_forecasts %>%
    group_by(date, NewMoonNumber, forecastmonth, forecastyear,level, currency, species) %>%
    summarise(estimate = mean(estimate), LowerPI=mean(LowerPI), UpperPI=mean(UpperPI))
  ensemble$model='Ensemble'
  return(ensemble)
}

plot_sp_predicts = function(data, lvl, kind) {
  data = transform(data, forecast_date = as.yearmon(paste(forecastmonth, "/", forecastyear, sep =
                                                            ""), format = "%m/%Y")) %>% transform(Date = as.Date(Date, "%Y-%m-%d"))
  data1 = filter(data, level == lvl,
                 Date == max(as.Date(Date)))
  target_moon = min(data1$NewMoonNumber)
  data2 = filter(data1, NewMoonNumber == target_moon)
  title = paste(data2$forecast_date[2], lvl, sep = " ")
  plot_data(data2, title, kind)
}

plot_data = function(data, title, kind) {
  if (kind == 'forecast') {
    ggplot(data,
           aes(
             x = estimate,
             y = reorder(species, estimate),
             xmin = LowerPI,
             xmax = UpperPI
           )) +
      geom_point() +
      geom_errorbarh() +
      ggtitle(title) + # should make title better somehow
      ylab("Species") +
      xlab("Abundance")
  }
  else{
    print("not available")
  }
}

#' Ensure that a forecast file is in the correct format
#' 
#' Tools for working with forecast data expect a certain format.
#' This ensures a forecast file meets those formats. All column
#' and variable names are case sensitive. For specification see:
#' https://github.com/weecology/portalPredictions/wiki/forecast-file-format
#' 
#' @param forecast_df dataframe A dataframe read from a raw forecast file
#' @param verbose boolean Output warnings of specific violations
#' @return boolean

forecast_is_valid=function(forecast_df, verbose=FALSE){
  is_valid=TRUE
  violations=c()
  #Define valid valeus
  valid_columns = c('date','forecastmonth','forecastyear','NewMoonNumber','model','currency',
                    'level','species','estimate','LowerPI','UpperPI')
  valid_currencies = c('abundance','richness','biomass','energy')
  valid_levels = paste('Plot',1:24,' ', sep = '')
  valid_levels = c('All','Controls','FullExclosure','KratExclosure', valid_levels)
  valid_species = c('total','BA','DM','DO','DS','OL','OT','PB','PE','PF','PH','PI','PL','PM','PP','RF','RM','RO','SF','SH','SO','NA')
  
  #Colnames should match exactly, case and everything, no more, no less.
  #The rest of the check depend on valid column names, so bail out early
  #if this does not pass. 
  if(!(all(colnames(forecast_df) %in% valid_columns) & all(valid_columns %in% colnames(forecast_df)))){
    if(verbose) print('Forecast file column names invalid')
    return(FALSE)
  }
  
  #date must be in the format YYYY-MM-DD. as.Date() will return NA if it
  #doesn't match this exactly. 
  #TODO: Account for dates that are formatted correctly but potentially many years off.
  forecast_df$date = base::as.Date(forecast_df$date, '%Y-%m-%d')
  if(any(is.na(forecast_df$date))) { is_valid=FALSE; violations = c('date', violations) }
  
  #All of these must be ones listed in the forecast format wiki. 
  if(!all(unique(forecast_df$currency) %in% valid_currencies)) { is_valid=FALSE; violations = c('currency', violations) }
  if(!all(unique(forecast_df$level) %in% valid_levels)) { is_valid=FALSE; violations = c('level', violations) }
  if(!all(unique(forecast_df$species) %in% valid_species)) { is_valid=FALSE; violations = c('species', violations) }
  
  #Estimates and PI's cannot have NA values
  if(any(is.na(forecast_df$estimate))) { is_valid=FALSE; violations = c('NA esimates', violations) }
  if(any(is.na(forecast_df$LowerPI))) { is_valid=FALSE; violations = c('NA LowerPI', violations) }
  if(any(is.na(forecast_df$UpperPI))) { is_valid=FALSE; violations = c('NA UpperPI', violations) }
  
  if(verbose & length(violations)>0) print(paste('Forecast validation failed: ', violations), sep='')
  return(is_valid)
}


#' Collect all seperate forecasts file into a single dataframe.
#' 
#' The base folder can include subfolders.
#' Will only include files which pass validation. Will issue 
#' warnings if a file isn't valid. If verbose is True it will
#' print specifics about the validation.
#' 
#' @param forecast_folder str Base folder holding all forecast files
#' @param verbose bool Output info on file violations
#' @return dataframe combined forecasts
compile_forecasts=function(forecast_folder='./predictions', verbose=FALSE){
  forecast_filenames = list.files(forecast_folder, full.names = TRUE, recursive = TRUE)
  all_forecasts=data.frame()
  
  for(this_forecast_file in forecast_filenames){
    this_forecast_data = try(read.csv(this_forecast_file, na.strings = '', stringsAsFactors = FALSE))
    if(class(this_forecast_data) %in% 'try-error'){
      if(verbose){
        print(paste('File not readable: ',this_forecast_file, sep=''))
      } else {
        warning(paste('File not readable: ',this_forecast_file, sep=''))
      }
      next
    }
    
    if(verbose) print(paste('Testing file ',this_forecast_file,sep=''))
    if(forecast_is_valid(this_forecast_data, verbose=verbose)){
      if(verbose) {
        print(paste('File format is valid: ', this_forecast_file, sep=''))
        print('-------')
      }
      all_forecasts = all_forecasts %>%
        dplyr::bind_rows(this_forecast_data)
    } else {
      if(verbose){
        print(paste('File format not valid: ', this_forecast_file, sep=''))
        print('-------')
      } else{
        warning(paste('File format not valid: ', this_forecast_file, sep=''))
      }
    }
  }
  
  return(all_forecasts)
}

