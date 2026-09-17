# Question 1
USE sales;
CREATE TABLE students (
	id INT PRIMARY KEY,
    fullName VARCHAR(100),
    age INT
    );

# Question 2
USE sales;
START TRANSACTION;
INSERT INTO students (id, fullName, age)
VALUES
	(1, 'John Mark', 18),
	(2, 'Lokopir Chonjo', 17),
	(3, 'Lokolita Lokor', 20);
COMMIT;

# Question 3
USE sales;
START TRANSACTION;
UPDATE students
SET age = 20
WHERE id = 2;
COMMIT;
