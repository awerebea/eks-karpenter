output "private-subnet-az1" {
  value = aws_subnet.private-az1.id
}

output "private-subnet-az2" {
  value = aws_subnet.private-az2.id
}

output "public-subnet-az1" {
  value = aws_subnet.public-az1.id
}

output "public-subnet-az2" {
  value = aws_subnet.public-az2.id
}
