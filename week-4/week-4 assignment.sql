# Advanced SQL Queries and Aggregations
# Question 1
USE sales;
SELECT paymentDate,
SUM(amount) AS totalAmount
FROM payments
GROUP BY paymentDate
ORDER BY paymentDate DESC
LIMIT 5;

# Question 2
USE sales;
SELECT customerName,
country,
AVG(creditLimit) AS avgcreditLimit
FROM customers
GROUP BY customerName, country;

# Question 3
USE sales;
SELECT productCode,
quantityOrdered,
SUM(quantityOrdered*priceEach) AS totalPrice
FROM orderdetails
GROUP BY productCode, quantityOrdered;

#Question 4
USE sales;
SELECT
	checkNumber,
  MAX(amount) AS highestAmount
FROM payments
GROUP BY checkNumber

