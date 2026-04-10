select * from sample_superstore


----------------------------------- Data Exploration ---------------------------------------
select 
COUNT(distinct Order_ID) as total_orders,
COUNT(distinct Customer_ID ) as total_customers,
MIN(Order_Date) as earliest_order_date,
MAX(Order_Date) as latest_order_date,
ROUND(SUM(Sales),2) as Total_Sales,
ROUND(sum(Profit),2) as Total_Profit
from sample_superstore;

select distinct Category, Sub_Category from sample_superstore order by Category;
select distinct Region, Segment from sample_superstore order by Region;


------------------------------ Core Analysis -------------------------------------------
-- Step 1. Creating a base table.
WITH rfm_base as(
	select
		Customer_ID,Customer_Name,
		MAX(Order_Date) as lateset_order_date,
		DATEDIFF(DAY,Max(Order_Date),'2017-12-31') as recency_days,
		COUNT(distinct Order_ID) as frequency,
		ROUND(SUM(Sales),2) as monetry
	from sample_superstore
	group by Customer_ID, Customer_Name
),
-- Step 2. Score each customer based on 1-4 dimension.
rfm_score as (
	select *,
		NTILE(4) over(order by recency_days desc) as r_score,
		NTILE(4) over(order by frequency asc) as f_score,
		NTILE(4) over(order by monetry asc) as m_score
	from rfm_base
),
-- Step 3. Combine rfm scores into a segment label.
rfm_segments as(
	select *,
		(r_score+ f_score+ m_score ) as rfm_total,
		case 
			when r_score=4 and f_score=4 and m_score=4 then 'Champion customer'
			when r_score >=3 and f_score >=3 then 'Loyal Customer'
			when r_score >=3 and f_score <=2 then 'Promising Customer'
			when r_score >=2 and f_score >=2 then 'At Risk'
			when r_score <= 2 AND f_score <= 2 AND m_score >= 3 then 'Can not lose them'
			when r_score= 1 then 'Lost'
			Else 'Need Attention' 
		end as rfm_segment
	from rfm_score
)
select * from rfm_segments order by rfm_total desc;



-------------------------------------- Sales Rep Analysis -------------------------
with sales_rep as(
	select
		p.Regional_Manager as sales_rep,
		s.Region,
		COUNT(DISTINCT order_id)            AS total_orders,
				COUNT(DISTINCT customer_id)         AS unique_customers,
				ROUND(SUM(sales), 2)                AS total_revenue,
				ROUND(SUM(profit), 2)               AS total_profit,
				ROUND(SUM(profit) / SUM(sales) * 100, 2) AS profit_margin_pct,
				ROUND(AVG(discount) * 100, 2)       AS avg_discount_pct
	from sample_superstore as s
	left join people_data as p
	on s.Region = p.Region
	group by p.Regional_Manager, s.Region
),
ranked as(
	SELECT *,
		RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
		RANK() OVER (ORDER BY profit_margin_pct DESC) AS margin_rank
from sales_rep
)
select *, 
 -- Flag reps who rank high on revenue but low on margin
    -- (they are discounting too heavily to close deals)
    CASE
        WHEN revenue_rank <= 3 AND margin_rank > 3 THEN 'High Revenue, Low Margin — Review Discounting'
        WHEN revenue_rank <= 3 AND margin_rank <= 3 THEN 'Top Performer'
        WHEN revenue_rank > 3 AND margin_rank <= 3 THEN 'Efficient but Low Volume'
        ELSE 'Needs Coaching'
    END AS rep_flag
 from ranked;



--------------------- Monthly Trends ----------------------
With Monthly_data as
	(select
	    MONTH(Order_Date) as month_num,
		DATENAME(MONTH,Order_Date) as Month_name,
		round(SUM(Sales),2) as Revenue,
		ROUND(SUM(Profit),2) as Profit,
		CONCAT( ROUND((SUM(Profit) )/ SUM(Sales) ,2)*100,'%') as Profit_margin
	from sample_superstore
	group by DATENAME(MONTH,Order_Date),MONTH(Order_Date)
)
select *,
	concat(round(((Profit - LAG(Profit) over(order by month_num asc)) / NullIF( LAG(Profit) over(order by month_num asc),0 ) )*100,2),'%')  as change_in_Profit
from Monthly_data
order by month_num



-- Customers who were previously active but haven't ordered in 6+ months
WITH customer_activity AS (
    SELECT
        customer_id,
        customer_name,
        segment,
        MAX(order_date)                         AS last_order_date,
        DATEDIFF(DAY,MAX(order_date),'2027-12-01') AS days_since_last_order,
        COUNT(DISTINCT order_id)                AS total_orders,
        ROUND(SUM(sales), 2)                    AS lifetime_value
    FROM sample_superstore
    GROUP BY customer_id, customer_name, segment
)
SELECT *,
    CASE
        WHEN days_since_last_order BETWEEN 180 AND 365
            THEN 'At Risk'
        WHEN days_since_last_order > 365
            THEN 'Churned'
        WHEN days_since_last_order BETWEEN 90 AND 179
            THEN 'Watch Closely'
        ELSE 'Active'
    END AS churn_status
FROM customer_activity
WHERE days_since_last_order >= 90
ORDER BY lifetime_value DESC;