variable "name" {}
variable "ami_id" {}
variable "instance_type" {}
variable "key_name" {}
variable "rancher_ssl_cert" {}
variable "rancher_ssl_key"  {}
variable "rancher_ssl_chain"  {}
variable "database_port"    {}
variable "database_name"    {}
variable "database_username" {}
variable "database_password" {}
variable "database_encrypted_password" {}
variable "ha_encryption_key" {}
variable "scale_min_size" {}
variable "scale_max_size" {}
variable "scale_desired_size" {}
variable "ha_registration_url" {}
variable "region" {}
variable "vpc_id" {}
variable "az1" {}
variable "az2" {}
variable "az3" {}
 
#Create Security group for access to RDS instance
resource "aws_security_group" "rancher_ha_allow_db" {
  name = "rancher_ha_allow_db"
  description = "Allow Connection from internal"
  vpc_id = "${var.vpc_id}"
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = "${var.database_port}"
    to_port = "${var.database_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}
#Create RDS database
resource "aws_db_instance" "rancherdb" {
  allocated_storage    = 10
  engine               = "mysql"
  instance_class       = "db.t2.small" #This is smaller than the recommended size and should be increased according to environment
  name                 = "${var.database_name}"
  username             = "${var.database_username}"
  password             = "${var.database_password}"
  vpc_security_group_ids = ["${aws_security_group.rancher_ha_allow_db.id}"]
  }

resource "aws_iam_server_certificate" "rancher_ha"
 {
  name             = "rancher-ha-cert"
  certificate_body = "${file("${var.rancher_ssl_cert}")}"
  private_key      = "${file("${var.rancher_ssl_key}")}"
  certificate_chain = "${file("${var.rancher_ssl_chain}")}"

  provisioner "local-exec" {
    command = <<EOF
      echo "Sleep 10 secends so that the cert is propagated by aws iam service"
      echo "See https://github.com/hashicorp/terraform/issues/2499 (terraform ~v0.6.1)"
      sleep 10
EOF
  }
}

# Into ELB from upstream
resource "aws_security_group" "rancher_ha_web_elb" {
  name = "rancher_ha_web_elb"
  description = "Allow ports rancher "
  vpc_id = "${var.vpc_id}"
   egress {
     from_port = 0
     to_port = 0
     protocol = "-1"
     cidr_blocks = ["0.0.0.0/0"]
   }
   ingress {
      from_port = 443
      to_port = 443
      protocol = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
   }
}

#Into servers
resource "aws_security_group" "rancher_ha_allow_elb" {
  name = "rancher_ha_allow_elb"
  description = "Allow Connection from elb"
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
      from_port = 81 
      to_port = 81 
      protocol = "tcp"
      security_groups = ["${aws_security_group.rancher_ha_web_elb.id}"]
  }
ingress {
      from_port = 444 
      to_port = 444 
      protocol = "tcp"
      security_groups = ["${aws_security_group.rancher_ha_web_elb.id}"]
  }
}

#Direct into Rancher HA instances
resource "aws_security_group" "rancher_ha_allow_internal" {
  name = "rancher_ha_allow_internal"
  description = "Allow Connection from internal"
  vpc_id = "${var.vpc_id}"
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group_rule" "ingress_all_rancher_ha" {
    security_group_id = "${aws_security_group.rancher_ha_allow_internal.id}"
    type = "ingress"
    from_port = 0
    to_port = "0" 
    protocol = "-1"
    source_security_group_id = "${aws_security_group.rancher_ha_allow_internal.id}"
}

resource "aws_security_group_rule" "egress_all_rancher_ha" {
    security_group_id = "${aws_security_group.rancher_ha_allow_internal.id}"
    type = "egress"
    from_port = 0
    to_port = 0 
    protocol = "-1"
    source_security_group_id = "${aws_security_group.rancher_ha_allow_internal.id}"
}
# User-data template
resource "template_file" "user_data" {

    template = "${file("${path.module}/files/userdata.template")}"

    vars {

        # Database
        database_address  = "${aws_db_instance.rancherdb.address}"
        database_port     = "${var.database_port}"
        database_name     = "${var.database_name}"
        database_username = "${var.database_username}"
        database_password = "${var.database_password}"
        database_encrypted_password = "${var.database_encrypted_password}"
        ha_registration_url = "${var.ha_registration_url}" 
        scale_desired_size = "${var.scale_desired_size}" 
	#Rancher HA encryption key
	encryption_key    = "${var.ha_encryption_key}"
    }

    lifecycle {
        create_before_destroy = true
    }

}

provider "aws" {
    region = "${var.region}"
}

# Elastic Load Balancer
resource "aws_elb" "rancher_ha" {
  name = "rancher-ha"
  availability_zones = ["${var.az1}","${var.az2}","${var.az3}"]
  cross_zone_load_balancing = true 
  internal = false
  security_groups = ["${aws_security_group.rancher_ha_web_elb.id}"]
  listener {
    instance_port = 81 
    instance_protocol = "tcp"
    lb_port = 443
    lb_protocol = "ssl"
    ssl_certificate_id = "${aws_iam_server_certificate.rancher_ha.arn}"
  }
  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 4
    timeout = 15
    target = "TCP:81"
    interval = 60
  }

  cross_zone_load_balancing = true 
}
resource "aws_proxy_protocol_policy" "rancher_ha" {
	  load_balancer = "${aws_elb.rancher_ha.name}"
	    instance_ports = ["81", "444"]
    }

# rancher resource
resource "aws_launch_configuration" "rancher_ha" {
    name_prefix = "Launch-Config-rancher-server-ha"
    image_id = "${var.ami_id}"
    security_groups = [ "${aws_security_group.rancher_ha_allow_elb.id}",
                        "${aws_security_group.rancher_ha_web_elb.id}",
			"${aws_security_group.rancher_ha_allow_internal.id}"]
    #security_groups = [ "sg-1501fb72"]
    instance_type = "${var.instance_type}"
    key_name      = "${var.key_name}"
    user_data     = "${template_file.user_data.rendered}"
    associate_public_ip_address = false
    ebs_optimized = false

}

resource "aws_autoscaling_group" "rancher_ha" {
  name   = "${var.name}-asg"
  min_size = "${var.scale_min_size}"
  max_size = "${var.scale_max_size}" 
  desired_capacity = "${var.scale_desired_size}" 
  health_check_grace_period = 900
  health_check_type = "ELB"
  force_delete = false 
  launch_configuration = "${aws_launch_configuration.rancher_ha.name}"
  load_balancers = ["${aws_elb.rancher_ha.name}"]
  availability_zones = ["${var.az1}","${var.az2}","${var.az3}"]
  tag {
    key = "Name"
    value = "${var.name}"
    propagate_at_launch = true
  }

}

output "elb_dns"      { value = "${aws_elb.rancher_ha.dns_name}" } 
