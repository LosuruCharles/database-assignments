# Question 1: Retrieve Payment Information
USE sales;
SELECT checkNumber, paymentDate, amount
FROM payments;

# Question 2: Find Orders in Process
USE sales;
SELECT orderDate, requiredDate, status
FROM orders
WHERE status = 'In Process'
ORDER BY orderDate DESC;

# Question 3: Find Sales Representatives
USE sales;
SELECT firstName, lastName, email
FROM employees
WHERE jobTitle = 'Sales Rep'
ORDER BY employeeNumber DESC;

# Question 4: Retrieve Office Information
USE sales;
SELECT *
FROM offices;

# Question 5: Retrieve the Five Cheapest Products
USE sales;
SELECT productName, quantityInStock
FROM products
ORDER BY buyPrice ASC
LIMIT 5;
