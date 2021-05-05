provider "aws" {
 region     = "ap-south-1"
 profile    = "raja"
}

# Create key-pair
resource "tls_private_key" "test" {
  algorithm   = "RSA"
}
# locally store
resource "local_file" "web" {
    content     = tls_private_key.test.public_key_openssh
    filename = "mykey.pem"
    //file_permission = 0400
}
 
# Create new aws key_pair
resource "aws_key_pair" "test_key" {
  key_name   = "mykey"
  public_key = tls_private_key.test.public_key_openssh
}

#Create Security group
resource "aws_security_group" "wordgroup" {
   name = "my security gp"
  ingress {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    protocol  = "tcp"
    from_port = 2049
    to_port   = 2049
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
 }
tags = {
    Name = "allow_tcp and nfs"
  }
}


#launch instance
resource "aws_instance" "myin" {
 
 ami           = "ami-0732b62d310b80e97"
 instance_type = "t2.micro"
 key_name = aws_key_pair.test_key.key_name
 security_groups = ["${aws_security_group.wordgroup.name}"]
tags = {
  Name = "EFSOs"
  }
 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.test.private_key_pem
    host     = aws_instance.myin.public_ip
  }
 provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd" 
    ]
  }
}


#Create efs
resource "aws_efs_file_system" "myefs" {
  creation_token = "my-efs"
tags = {
    Name = "Task2-efs"
  }
 depends_on = [ aws_security_group.wordgroup, aws_instance.myin, ]
}
resource "aws_efs_mount_target" "alpha" {
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id      = aws_instance.myin.subnet_id
  security_groups = ["${aws_security_group.wordgroup.id}"]
depends_on = [ aws_efs_file_system.myefs,]

}


#Mount EFS volume in EC2 instance and clone code from GitHub
resource "null_resource" "local2" {
 depends_on = [
    aws_efs_mount_target.alpha,
  ]
 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.test.private_key_pem
    host     = aws_instance.myin.public_ip
  }
 provisioner "remote-exec" {
    inline = [
      "sudo yum install -y amazon-efs-utils",
"sudo mount -t efs ${aws_efs_file_system.myefs.id}:/ /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo curl https://github.com/Ds123-wq/cloudtask-2/blob/master/index.html  > index.html ",
        "sudo cp index.html   /var/www/html/" ,
    ]
  }

}


# Create s3 bucket
resource "aws_s3_bucket" "bucket" {
  depends_on = [ null_resource.local2, ]
  bucket = "mybuckets312"
  acl = "public-read" 
}

//Give public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.bucket.id
}
//Upload image downloaded from gihub repo to S3 bucket
resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.bucket.id
  key    = "apache-web-server.png"
  source = "C:/Users/Dell/Desktop/terra/task-2/images/apache-web-server.png"
  content_type = "image/jpeg"
  acl = "public-read"
depends_on = [ 
      null_resource.local2,
      aws_s3_bucket.bucket,
]
}



//Create CloudFront  for S3 bucket
resource "aws_cloudfront_origin_access_identity" "oai" {
    comment = "cloudfront creation"
}
locals {
  s3_origin_id = "S3-${aws_s3_bucket.bucket.bucket}"
}
//Create CloudFront distribution with S3 bucket as origin
resource "aws_cloudfront_distribution" "s3_distribution" {
 
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }
enabled             = true
default_root_object ="index.html"
default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
forwarded_values {
      query_string = false
cookies {
        forward = "none"
      }
    }
viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 9600
    max_ttl                = 86400
  }

restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["US", "CA", "GB", "DE"]
    }
 }
  
viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "null_resource" "loca1" {
connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.myin.public_ip
        port    = 22
        private_key =tls_private_key.test.private_key_pem
    }

provisioner "remote-exec" {
        inline  = [
            "sudo su << EOF",
             "echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key}' width = '300' height = '200'>\" >> /var/www/html/index.html",
            "EOF"
        ]

   }
depends_on = [
  aws_cloudfront_distribution.s3_distribution,
  ]

provisioner "local-exec" {
  command = "chrome ${aws_instance.myin.public_ip}"

}
}