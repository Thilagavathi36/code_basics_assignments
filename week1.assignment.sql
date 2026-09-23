----1. Voltkart's commercial team wants a quick look at the biggest sales. Return the
----top 20 completed orders by value, with the customer and the sales rep behind each one.
----Required output: order_id, order_date, customer_name, sales_rep_name, order_total.

SELECT TOP 20
    o.order_id,
    o.order_date,
    c.customer_name,
    e.employee_name AS sales_rep_name,
    o.order_total
FROM fact_orders o
INNER JOIN dim_employee e
    ON o.sales_rep_id = e.employee_id
INNER JOIN dim_customer c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'Completed'
  AND e.role = 'Sales Rep'
ORDER BY o.order_total DESC;


----2. Marketing wants to re-engage people who registered but never bought. List the
----customers who have never placed an order. Required output: customer_id,
----customer_name, signup_date.

select customer_id, customer_name, signup_date from dim_customer c
where NOT EXISTS(
select 1 from fact_orders o where o.customer_id = c.customer_id)


----3. Merchandising wants the stars of each category. For every category, return the
----top 3 products by completed revenue. Required output: category_name, product_name,
----total_revenunue_rank


SELECT * 
FROM (
    SELECT 
        category_name,
        product_name,
        SUM(line_amount) AS total_revenue,
        DENSE_RANK() OVER(
            PARTITION BY category_name 
            ORDER BY SUM(line_amount) DESC
        ) AS revenue_rank 
    FROM dim_product p
    INNER JOIN dim_category c 
        ON p.category_id = c.category_id
    INNER JOIN fact_order_items o 
        ON o.product_id = p.product_id
    INNER JOIN fact_orders fo 
        ON fo.order_id = o.order_id 
    WHERE fo.order_status = 'Completed'
    GROUP BY category_name, product_name
) b 
WHERE b.revenue_rank <= 3;

--4. Finance wants the revenue trend with momentum. Produce
--monthly completed revenue with a cumulative running total and the month-over-month %
--change. Required output: order_month (YYYY-MM), monthly_revenue, running_total,
--mom_pct_change.

WITH total_rev AS
(
    SELECT
        DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1) AS order_month,
        SUM(order_total) AS monthly_revenue
    FROM fact_orders
    WHERE order_status = 'completed'
    GROUP BY DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
),
running_total as(
select order_month,monthly_revenue,
sum(monthly_revenue )over(
order by order_month
rows between unbounded preceding and current row
)as running_month_total,
lag(monthly_revenue)OVER(
order by order_month)as previous_month
from total_rev
), 
month_over_month as(
select order_month,monthly_revenue , previous_month,running_month_total,
   ROUND(
        (monthly_revenue - previous_month)
        * 100.0
        / NULLIF(previous_month, 0),
        2
    ) AS mom_pct_change
from running_total

)

select order_month,running_month_total, mom_pct_change from month_over_month
order by order_month


--5. The CRM team wants to size up the customer base by value. Split customers into
--four quartiles by lifetime completed spend, and for each quartile report how many
--customers fall in it and their average spend. Required output: spend_quartile,
--customer_count, avg_lifetime_spend.

WITH order_total_customer as
(
select customer_id,
sum(order_total)as total_rev from fact_orders
where order_status = 'completed'
group by customer_id
), 
group_by as
(select customer_id, total_rev,
NTILE(4)OVER(
order by total_rev
)as grp
from order_total_customer
),
count_of_customer as(
select count(customer_id) as customer_count, AVG(total_rev) as avg_lifetime_spend
from group_by
group by grp
)
select * from count_of_customer




--6. The catalogue team needs to see everything under a part of the tree. Using a
--recursive query, list all categories in the subtree rooted at 'Computers' at any depth, with
--how deep each sits and a readable path from Computers. Required output: category_id,
--category_name, depth_level, category_path.

WITH category_hierarchy AS
(
    -- Anchor: Computers
    SELECT
        category_id,
        category_name,
        0 AS depth_level,
        CAST(category_name AS VARCHAR(MAX)) AS category_path
    FROM dim_category
    WHERE category_name = 'Computers'

    UNION ALL

    -- Recursive: children
    SELECT
        d.category_id,
        d.category_name,
        h.depth_level + 1,
        CAST(
            CONCAT(
                h.category_path,
                ' -> ',
                d.category_name
            ) AS VARCHAR(MAX)
        ) AS category_path
    FROM dim_category d
    JOIN category_hierarchy h
        ON d.parent_category_id = h.category_id
)
SELECT
    category_id,
    category_name,
    depth_level,
    category_path
FROM category_hierarchy;



--7. Sales leadership wants performance rolled up the org chart. For every employee,
--Codebasics · Data Engineering Bootcamp Page 1
--compute the total completed order value generated by their whole team — that is,
--themselves plus everyone reporting under them at any depth. A Sales Rep's team is just
--themselves; a manager's is their entire subtree. Required output: employee_id,
--employee_name, role, team_total_revenue.


WITH employee_tree AS
(
    SELECT
        employee_id AS root_employee_id,
        employee_name AS root_employee_name,
        employee_id AS member_employee_id
    FROM dim_employee

    UNION ALL

    SELECT
        t.root_employee_id,
        t.root_employee_name,
        e.employee_id
    FROM employee_tree t
    JOIN dim_employee e
        ON e.manager_id = t.member_employee_id
)
SELECT
    t.root_employee_id AS employee_id,
    t.root_employee_name AS employee_name,
    e.role,
    COALESCE(SUM(o.order_total), 0) AS team_total_revenue
FROM employee_tree t
JOIN dim_employee e
    ON e.employee_id = t.root_employee_id
LEFT JOIN fact_orders o
    ON o.sales_rep_id = t.member_employee_id
    AND o.order_status = 'Completed'
GROUP BY
    t.root_employee_id,
    t.root_employee_name,
    e.role
ORDER BY
    t.root_employee_id;

--8. The platform team is moving off nightly full reloads. You've been handed today's
--batch in stg_orders_incr. Write a single MERGE that performs an incremental load into
--fact_orders: update orders that changed, insert ones that are new. Acceptance criteria: one
--MERGE statement; matched orders are updated (status and total) and new orders inserted;
--include a verification query showing the fact_orders row count before versus after and a
--sample of updated rows.

MERGE INTO dbo.fact_orders as tgt
USING dbo.stg_orders_incr as src
on tgt.order_id = src.order_id

WHEN MATCHED AND (
ISNULL (tgt.order_status,'') <> ISNULL (src.order_status,'')
OR ISNULL(tgt.order_total,'')<> ISNULL (src.order_total,'')
)
THEN UPDATE SET
tgt.order_status = src.order_status,
tgt.order_total = src.order_total

WHEN NOT MATCHED BY TARGET THEN
INSERT (order_id, order_date, customer_id, sales_rep_id, order_status, order_total)
VALUES (src.order_id, src.order_date, src.customer_id, src.sales_rep_id, src.order_status, src.order_total);

--Forgot to take the evidence


--9.s The catalogue source now emits a change feed (cdc_product_changes) with
--operation codes. Apply it to dim_product in a single MERGE that honours the code I inserts
--a new product, U updates an existing one, D deletes it. Acceptance criteria: one MERGE
--handling all three operations; include a verification query showing inserted, updated, and
--deleted products.

select * into dim_product_temp from dim_product --400 rows



MERGE INTO dbo.dim_product_temp AS tgr
USING dbo.cdc_product_changes AS src
ON tgr.product_id = src.product_id

-- U: existing product → update
WHEN MATCHED AND src.operation = 'U' THEN
    UPDATE SET
        tgr.product_name = src.product_name,
        tgr.category_id = src.category_id,
        tgr.unit_price = src.unit_price,
        tgr.unit_cost    = src.unit_cost,
        tgr.launch_date  = src.launch_date

-- D: existing product → delete
WHEN MATCHED AND src.operation = 'D' THEN
    DELETE

-- I: new product → insert
WHEN NOT MATCHED BY TARGET AND src.operation = 'I' THEN
    INSERT (
        product_id,
        product_name,
        category_id,
        unit_price,
         unit_cost, launch_date
    )
    VALUES (
        src.product_id,
        src.product_name,
        src.category_id,
        src.unit_price,
        src.unit_cost, 
        src.launch_date
    );

SELECT * FROM dim_product_temp;
SELECT * FROM CDC_product_changes -- 35 ROWS updated

--10. A report is slow. Here is the query analysts are running:
-- SELECT o.customer_id, COUNT(*) AS orders_2024,
-- (SELECT SUM(oi.line_amount)
-- FROM fact_order_items oi
-- JOIN fact_orders o2 ON o2.order_id = oi.order_id
-- WHERE o2.customer_id = o.customer_id) AS lifetime_value
-- FROM fact_orders o
-- WHERE YEAR(o.order_date) = 2024
-- GROUP BY o.customer_id;
--Turn on SET STATISTICS IO, TIME ON and "Include Actual Execution Plan", run it, then make
--it fast: explain what the plan is doing, rewrite the query, and add an index that helps. Required
--output: the rewritten query, the CREATE INDEX statement(s), and a short note giving the
--logical reads before versus after and why the plan changed.


SET STATISTICS IO, TIME ON

----Slow Query
SELECT 
    o.customer_id, COUNT(*) AS orders_2024, 
    (SELECT SUM(oi.line_amount) 
     FROM fact_order_items oi 
     JOIN fact_orders o2 ON o2.order_id = oi.order_id 
     WHERE o2.customer_id = o.customer_id) AS lifetime_value 
FROM fact_orders o 
WHERE YEAR(o.order_date) = 2024 -- here is the pain point where it uses the YEAR() 
GROUP BY o.customer_id;



----optimised query

CREATE NONCLUSTERED INDEX IX_fact_order_items_order_id_line_amount
    ON dbo.fact_order_items (order_id) INCLUDE (line_amount);

CREATE NONCLUSTERED INDEX IX_fact_orders_order_date_customer_id
    ON dbo.fact_orders (order_date) INCLUDE (customer_id);

WITH Orders2024 AS (
    SELECT 
        o.customer_id,
        COUNT(*) AS orders_2024
    FROM dbo.fact_orders o
    WHERE o.order_date >= '2024-01-01' 
      AND o.order_date <  '2025-01-01'   
    GROUP BY o.customer_id
),
Customer_lifetime_value AS (
    SELECT 
        o.customer_id,
        SUM(oi.line_amount) AS lifetime_value
    FROM dbo.fact_orders o
    JOIN dbo.fact_order_items oi ON oi.order_id = o.order_id
    GROUP BY o.customer_id
)
SELECT 
    c.customer_id,
    c.orders_2024,
    l.lifetime_value
FROM Orders2024 c
LEFT JOIN Customer_lifetime_value l ON l.customer_id = c.customer_id;

--The optimization replaced the fact_orders nonclustered index scan with an index seek by making the date predicate SARGable.
--The fact_orders logical reads decreased from 274 to 230, while execution-plan operator times also decreased for the major hash operations.
--However, overall elapsed time improved only marginally from 40.35s to 39.34s because the query still performs a full scan of fact_orders and an index scan of fact_order_items.


--11. (Bonus) The retention team wants loyalty streaks. For each customer, find the
--longest run of consecutive calendar months in which they placed at least one completed
--order. Required output: customer_id, customer_name, longest_streak_months.

WITH completed_order_months AS(
	SELECT d.customer_id, d.customer_name, DATETRUNC(month,o.order_date) as order_mth
	FROM 
	dim_customer d INNER JOIN fact_orders o ON d.customer_id = o.customer_id
	WHERE order_status = 'Completed'
	GROUP BY d.customer_id, d.customer_name, DATETRUNC(month,o.order_date)
),
month_gap_flags AS(
	SELECT 
		customer_id, customer_name, order_mth, LAG(order_mth) OVER(PARTITION BY customer_id, customer_name ORDER BY order_mth) as prev_mth,
		CASE 
			WHEN DATEDIFF(month,LAG(order_mth) OVER(PARTITION BY customer_id, customer_name ORDER BY order_mth), order_mth) = 1 OR 
				 LAG(order_mth) OVER(PARTITION BY customer_id, customer_name ORDER BY order_mth) IS NULL THEN 0 
			ELSE 1
		END as flag
	FROM completed_order_months
),
streak_groups AS(
	SELECT *, SUM(flag) OVER(PARTITION BY customer_id, customer_name ORDER BY order_mth) as grp_id
	FROM month_gap_flags
),
customer_streaks AS(
	SELECT 
		customer_id, customer_name, COUNT(1) as monthly_streaks
	FROM streak_groups
	GROUP BY customer_id, customer_name, grp_id
)

-- SELECT * FROM customer_streaks;
SELECT customer_id, customer_name, MAX(monthly_streaks) as longest_streak 
FROM customer_streaks
GROUP BY customer_id, customer_name;