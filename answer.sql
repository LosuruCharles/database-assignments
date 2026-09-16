CREATE DATABASE school_management_system;
USE school_management_system;
CREATE TABLE students_statement; (
    student_id           INT AUTO_INCREMENT PRIMARY KEY,
    first_name           VARCHAR(50) NOT NULL,
    last_name            VARCHAR(50) NOT NULL,
    date_of_birth        DATE NOT NULL,
    gender               ENUM('Male', 'Female', 'Other') NOT NULL,
    email                VARCHAR(100) UNIQUE,
    phone                VARCHAR(20),
    address              VARCHAR(255)
  )
