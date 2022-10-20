library(flexdashboard)
library(htmltools)
library(lubridate)
library(data.table)
library(highcharter)
library(dplyr)
library(readr)
library(RODBC) 
library(readxl)
library(reshape2)

daily_estimates_data <- '2022-01-23'


when_updated_func <- function(report_name, date){

  last_updated = as.numeric(lubridate::today() - ymd(date))
  
  if(last_updated <= 7){
    return(h5(last_updated, color = 'green'))
  } else if (last_updated > 7, last_updated <= 20) {
    return(h5(last_updated, color = 'blue'))
  } else {
    return(h5(last_updated, color = 'red'))
  }
  
  
  
}


trips_by_borough <- setDT(sqlQuery(policy_con,
                                   "SELECT 
      [metric_month]
      ,[industry]
      ,trips.[zone]

      ,[borough]
      ,[count_pickups]
   
  FROM [TLC_Policy_Programs_Dev].[dbo].[industry_zone_indicators_monthly_pickups] trips
  inner join geography_lookup_zone loc
  ON trips.zone = loc.locationid
"))


report_last_updated <- when_updated_func('weekly_numbers',daily_estimates_data)


#indicators-------------------------------------

industry_indicators_data <- fread('data/data_reports_monthly_01_21_2022.csv')

industry_indicators_data$weight <- 1
industry_indicators_data$`Month/Year` <- lubridate::ymd(paste0(industry_indicators_data$`Month/Year`,'-01'))
setDT(industry_indicators_data)
industry_indicators_data <- setDT(industry_indicators_data)[`License Class` == 'FHV - High Volume', `License Class`:= 'HVFHV']
industry_indicators_data <- setDT(industry_indicators_data)[`License Class` == 'FHV - Black Car',weight:= 0.32]
industry_indicators_data <- setDT(industry_indicators_data)[`License Class` == 'FHV - Livery',weight:= 0.65]
industry_indicators_data <- setDT(industry_indicators_data)[`License Class` == 'FHV - Lux Limo',weight:= 0.03]

industry_indicators_data <- setDT(industry_indicators_data)[`License Class` == 'FHV - Black Car', `License Class`:= 'FHV']
industry_indicators_data <- setDT(industry_indicators_data)[`License Class` == 'FHV - Livery', `License Class`:= 'FHV']
industry_indicators_data <- setDT(industry_indicators_data)[`License Class` == 'FHV - Lux Limo', `License Class`:= 'FHV']

industry_indicators_data$`Trips Per Day` <- as.numeric(gsub(",", "", industry_indicators_data$`Trips Per Day`))

industry_indicators_data$`Unique Drivers` <- as.numeric(gsub(",", "", industry_indicators_data$`Unique Drivers`))

industry_indicators_data$`Unique Vehicles` <- as.numeric(gsub(",", "", industry_indicators_data$`Unique Vehicles`))

#industry_indicators_data$`Avg Minutes per Trip` <- as.numeric( industry_indicators_data$`Avg Minutes per Trip`)
industry_indicators_data$`Avg Minutes Per Trip` <- as.numeric(gsub(",", "", industry_indicators_data$`Avg Minutes Per Trip`))

industry_indicators_data$`Percent of Trips Paid with Credit Card` <- as.numeric(gsub("%", "", industry_indicators_data$`Percent of Trips Paid with Credit Card`))
industry_indicators_data$`Trips Per Day Shared` <- as.numeric(gsub(",", "", industry_indicators_data$`Trips Per Day Shared`))



industry_indicators_data_fhv <- 
  industry_indicators_data %>%
  dplyr::filter(`License Class` == 'FHV') %>%
  dplyr::group_by(`Month/Year`,`License Class`) %>% 
  dplyr::summarise(trips= sum(`Trips Per Day`), 
                   unique_drivers = sum(`Unique Drivers`), 
                   unique_vehicles = sum(`Unique Vehicles`), 
                   avg_days_veh_on_road = sum(`Avg Days Vehicles on Road`*weight), 
                   avg_hours_per_day_veh = sum(`Avg Hours Per Day Per Vehicle`*weight), 
                   avg_mins_trip = sum(`Avg Minutes Per Trip`*weight), 
                   credit_card = sum(`Percent of Trips Paid with Credit Card`), 
                   shared_trips = sum(`Trips Per Day Shared`) )

industry_indicators_data <- 
  industry_indicators_data %>% 
  dplyr::filter(`License Class` != 'FHV') %>%
  dplyr::select(`Month/Year`,`License Class`,trips=`Trips Per Day`, unique_drivers = `Unique Drivers`,
                unique_vehicles = `Unique Vehicles`,
                avg_days_veh_on_road = `Avg Days Vehicles on Road`,
                avg_hours_per_day_veh = `Avg Hours Per Day Per Vehicle`, 
                avg_mins_trip = `Avg Minutes Per Trip`, 
                credit_card = `Percent of Trips Paid with Credit Card`, 
                shared_trips = `Trips Per Day Shared`) %>% dplyr::bind_rows(industry_indicators_data_fhv) %>% dplyr::arrange(`Month/Year`,`License Class`)
 

#Monthly Trips-------------------------------------------------------

policy_con = odbcConnect("TLC_Policy_Programs_Dev", uid = "voevodinn")

year_mon <- as.character(lubridate::floor_date(Sys.Date(),'month'))
year_mon_fhv <- as.character(lubridate::floor_date(Sys.Date(),'month') - months(1))

industries_data <- setDT(sqlQuery(policy_con,
                                  paste0("SELECT 
     
      DATEADD(MONTH, DATEDIFF(MONTH, 0, [metric_day]), 0) as year_month
      ,[industry] as industry
      ,sum([count_trips]) as count_trips
  FROM [TLC_Policy_Programs_Dev].[dbo].[industry_indicators_daily_trips]
  where [metric_day] <","'",year_mon,"'", " and [metric_day] >= '2012-01-01'
  GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, [metric_day]), 0),[industry]
")))

fhv_data <- industries_data[industries_data$industry %in% c('fhv_livery', 'fhv_black_car', 'fhv_lux_limo') & industries_data$year_month < year_mon_fhv,]
ind_data <- setDT(industries_data)[industry %in% c('fhv_livery', 'fhv_black_car', 'fhv_lux_limo'),industry:='fhv_traditional']
ind_data <- ind_data %>% dplyr::group_by(year_month, industry) %>% dplyr::summarise(count_trips = sum(count_trips))

date1 <- max(ind_data$year_month)
date2 <- date1 %m-% months(1)
date3 <- date1 %m-% months(12)

industries_filtered <- ind_data %>% dplyr::filter(year_month %in% c(date1,date2,date3))

colnames(fhv_data)[2] <- "company"


companies_data <- setDT(sqlQuery(policy_con,
paste0("SELECT 
      DATEADD(MONTH, DATEDIFF(MONTH, 0, [metric_day]), 0) as year_month
      ,[company] as company
      ,sum([count_pickups]) as count_trips
  FROM [TLC_Policy_Programs_Dev].[dbo].[submission_company_indicators_daily_trips]
  where company in ('UBER','LYFT','JUNO','VIA') and [metric_day] <","'",year_mon,"'", " and [metric_day] >= '2019-02-01'
  GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, [metric_day]), 0),[company]
")))

companies_data <- bind_rows(companies_data, fhv_data)
companies_data$company <- tolower(companies_data$company) 



data_exl <- read_excel("data/local_law_31.xlsx")
data_exl <- data_exl[-c(1:4),-c(2:19)]
library(janitor)
data_exl <- data_exl %>%
  row_to_names(row_number = 1)

data_exl <- data_exl[-c(1,3, 12,14,16,25,27,29,38,40,42,51,53,54),]
colnames(data_exl)[1] <- 'category'

data_exl <- data_exl[-c(10,20,30,40),]

vehs <- industry_indicators_data[,c(1,2,6)]
vehs$year_mon <- lubridate::ym(vehs$`Month/Year`)
vehs <- setDT(vehs)[`License Class` == 'Yellow', 
                    lic_no:='medallion'][`License Class` == 'FHV - High Volume',
                                         lic_no:='fhv'][`License Class` == 'Green',
                                                        lic_no:='shl'][`License Class` == 'FHV - Black Car',
                                                                       lic_no:='fhv'][`License Class` == 'FHV - Livery',
                                                                                      lic_no:='fhv'][`License Class` == 'FHV - Lux Limo',
                                                                                                     lic_no:='fhv']
vehs$`Unique Vehicles` <- as.numeric(gsub(",", "", vehs$`Unique Vehicles`))
vehs <- vehs %>% dplyr::group_by(year_mon, lic_no) %>% dplyr::summarise(vehicles = sum(as.numeric(`Unique Vehicles`)))


all_crashes <- setDT(data_exl)[c(1:9),]
all_crashes$category <- c('total_crashes', 'medallion','shl','unknown','fhv','fhv','fhv','van','paratransit')

all_crashes <- data.table::melt(setDT(all_crashes), id.vars = "category", variable.name = "year_mon")
all_crashes$year_mon <- lubridate::my(all_crashes$year_mon)
all_crashes <- all_crashes %>% dplyr::group_by(category,year_mon) %>% dplyr::summarise(total_crashes = sum(as.numeric(value)))


long <- data.table::melt(setDT(data_exl), id.vars = "category", variable.name = "year_mon")
long$year_mon <- lubridate::my(long$year_mon)
