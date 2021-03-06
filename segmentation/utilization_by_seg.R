# This is to extract historical "actual" utilization rate from database
# To calcualte the "model" utilization rate, extract it from QRM Detailed Forecast Audit report
# This file is slightly different from closure_by_seg becuase it does not need to check pair (consecutive) months
# for account closer as in closure rate

rm(list=ls())
req_packages = c("haven", "ggplot2", "xlsx")

for (req_pack_ele in req_packages) {
  if (!require(req_pack_ele, character.only = T)) {
    install.packages(req_pack_ele)
    library(req_pack_ele, character.only = T)
  }
}
is_export_xlsx = F


# Period 
# Serioulsly ?
# https://stackoverflow.com/questions/29956396/looping-through-date-in-r-loses-format
# Period from 2016-01-31 to 2018-02-31
# period = as.list(seq(as.Date("2016-02-01"),length=26,by="month")-1)
period = as.list(c(as.Date('2018-5-31')))
# period = as.list(seq(as.Date("2016-02-01"),length=10,by="month")-1)
period_str = c()

# Output (next month closure rate either by csegment or usegment)
# utilization_mat has seg1, 2, 3, 4, 5, 6, 7 for each period
utilization_mat = matrix(nrow = length(period), ncol=7)  
proposed_utilization_mat = matrix(nrow = length(period), ncol=7)  # For the proposed one

# sas_data fileds of interests
sas_fields = c('PERD_END_DT', 'Proc_Tp_RevNon_Ind', 'high_account_ID', 'QRM_Forecast_SubLOB', 
               'planning_account', 'QRM_LOB', 'Proc_Tp_RevNon_Ind', 'NonAccrualFlag', 'face_amt', 'Curr_Bal')

for (i in 1:length(period)) {
  
  period_str_ele = lapply(format(period[[i]], format="%b%Y"), tolower)
  period_str = c(period_str, period_str_ele)
  print(sprintf('Running sas data for %s', period_str_ele))
      
  temp_data = read_sas(paste0("data/comlmodeling_", period_str_ele, ".sas7bdat"))
  sas_data = temp_data[, sas_fields]
  
  # Initial filters for data relevant to utilization / closure
  period_filter = sas_data$PERD_END_DT >= period[[i]]
  revolver_filter = sas_data$Proc_Tp_RevNon_Ind == 'Revolver'
  sub_filter = !(sas_data$QRM_Forecast_SubLOB %in% c('Asset Sec Group', 'Direct Finance'))
  qrm_filter = sas_data$QRM_LOB != 'OTH'
  amt_filter = sas_data$face_amt >= 0
  sas_data = sas_data[period_filter & revolver_filter & sub_filter & qrm_filter & amt_filter,]
  
  # Set up filter for bbk-metro (only bbk-metro goes to seg 6 in proposed)
  names(temp_data) = tolower(names(temp_data))
  bbk_metro_filter_str =''
  if ('sub_lob_2_nm' %in% names(temp_data)) {  # new data
    sas_data['sub_lob_nm'] = temp_data[period_filter & revolver_filter & sub_filter & qrm_filter & amt_filter, 'sub_lob_2_nm']
    bbk_metro_filter_str = 'metro bbk'
    cat('\t', " -> sub_lob_nm field is patched by sub_lob_2_nm", '\n')
  } else {
    if ('Business Banking' %in% unique(temp_data$qrm_forecast_sublob)) {
      sas_data['sub_lob_nm'] = temp_data[period_filter & revolver_filter & sub_filter & qrm_filter & amt_filter, 'sub_lob_nm']
      bbk_metro_filter_str = 'metro business banking'
      cat('\t', "-> sub_lob_nm field is patched by SUB_LOB_NM", '\n')
    } else {
      # before Apr 2016 data
      # Old data has QRM_Forecast_SubLoB for BBK Metro and BBK Regional
      sas_data['sub_lob_nm'] = temp_data[period_filter & revolver_filter & sub_filter & qrm_filter & amt_filter, 'qrm_forecast_sublob']
      bbk_metro_filter_str = 'bbk metro'
      cat('\t', "-> sub_lob_nm field is patched by QRM_Forecast_SubLOB", '\n')
    }
  }
  
  # Assign USegment
  sas_data$USegment = NA
  
  # Segment filter
  abl_filter = grepl('ABL', sas_data$planning_account, ignore.case = T)
  biz_filter = grepl('Business', sas_data$QRM_Forecast_SubLOB, ignore.case = T)
  floor_filter = grepl('Floor', sas_data$planning_account, ignore.case = T)
  cib_filter = grepl('CIB', sas_data$QRM_LOB, ignore.case = T) & !abl_filter & !floor_filter
  cml_filter = grepl('CML', sas_data$QRM_LOB, ignore.case = T) & !abl_filter & !floor_filter &
    !biz_filter
  pwm_filter = grepl('PWM', sas_data$QRM_LOB, ignore.case = T) & !abl_filter & !floor_filter
  cnb_filter = (grepl('CNB', sas_data$QRM_LOB, ignore.case = T) | biz_filter) &
    !abl_filter & !floor_filter
  cre_filter = grepl('CRE', sas_data$QRM_LOB, ignore.case = T) & !abl_filter & !floor_filter
  
  # BBK-Metro filter (Updated filter setting for BBK-Metro)
  # BBK-Metro has been moved from CML (seg 3) to Rtl (seg 6)
  bbk_metro_filter = grepl(bbk_metro_filter_str, sas_data$sub_lob_nm, ignore.case = T)
  proposed_cml_filter = (grepl('CML', sas_data$QRM_LOB, ignore.case = T) & !abl_filter & !floor_filter) & !bbk_metro_filter
  proposed_cnb_filter = (grepl('CNB', sas_data$QRM_LOB, ignore.case = T) & !abl_filter & !floor_filter) | bbk_metro_filter
  
  sas_data[floor_filter, "USegment"] = 'Seg 1'
  sas_data[cib_filter, "USegment"] = 'Seg 2'
  sas_data[cml_filter, "USegment"] = 'Seg 3'
  sas_data[pwm_filter, "USegment"] = 'Seg 4'
  sas_data[abl_filter, "USegment"] = 'Seg 5'
  sas_data[cnb_filter, "USegment"] = 'Seg 6'
  sas_data[cre_filter, "USegment"] = 'Seg 7'
  
  sas_data[floor_filter, "Proposed_USeg"] = 'Seg 1'
  sas_data[cib_filter, "Proposed_USeg"] = 'Seg 2'
  sas_data[proposed_cml_filter, "Proposed_USeg"] = 'Seg 3'
  sas_data[pwm_filter, "Proposed_USeg"] = 'Seg 4'
  sas_data[abl_filter, "Proposed_USeg"] = 'Seg 5'
  sas_data[proposed_cnb_filter, "Proposed_USeg"] = 'Seg 6'
  sas_data[cre_filter, "Proposed_USeg"] = 'Seg 7'
  
  # Start period filter
  s_per_filter = with(sas_data, PERD_END_DT == period[[i]] & NonAccrualFlag == 'N' & face_amt > 0)
  s_per_data = sas_data[s_per_filter, ]
  s_per_data = aggregate(s_per_data[, c('face_amt', 'Curr_Bal')], 
                         by=list(new_id = paste0(s_per_data$high_account_ID, s_per_data$USegment), 
                                 USegment = s_per_data$USegment,
                                 Proposed_USeg = s_per_data$Proposed_USeg), 
                         FUN=sum)
  
  colnames(s_per_data) <- c("new_id", "USegment", "Proposed_USeg", "s_face_amt", "s_curr_bal")
  
  s_per_face_amt = with(s_per_data, tapply(s_face_amt, USegment, sum))
  s_per_bal_amt = with(s_per_data, tapply(s_curr_bal, USegment, sum))
  utilization_mat[i, 1:7] = s_per_bal_amt / s_per_face_amt * 100
  
  proposed_s_per_face_amt = with(s_per_data, tapply(s_face_amt, Proposed_USeg, sum))
  proposed_s_per_bal_amt = with(s_per_data, tapply(s_curr_bal, Proposed_USeg, sum))
  proposed_utilization_mat[i, 1:7] = proposed_s_per_bal_amt / proposed_s_per_face_amt * 100
}

# Make it n x 1 and add segmentation
utilization_df = data.frame(utilization=as.vector(t(utilization_mat)))

segmentation_name = c('seg1', 'seg2', 'seg3', 'seg4', 'seg5', 'seg6', 'seg7')

utilization_df['period'] = rep(unlist(period_str), each=length(segmentation_name))
utilization_df['segmentation'] = rep(segmentation_name, length(period_str))

ggplot(utilization_df, aes(x=period, y=utilization, group=segmentation)) + 
  geom_bar(aes(fill=segmentation), stat='identity', position='dodge') + 
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) + 
  scale_x_discrete(limits=unlist(period_str)) +
  theme(legend.position="bottom")

# Write to excel
if (is_export_xlsx == T) {
  write.xlsx(utilization_df, "utilization_by_seg.xlsx", sheetName="raw_data")
}
  
