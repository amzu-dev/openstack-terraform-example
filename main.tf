#I need a Ubuntu Image, so lets upload one to the Openstack

resource "openstack_images_image_v2" "ubuntu" {
  name             = "Ubuntu16"
  local_file_path  = "./ubuntu1604.img"
  verify_checksum  = false
  container_format = "bare"
  min_disk_gb      = 5
  min_ram_mb       = 512
  protected        = false
  disk_format      = "qcow2"
}



resource "openstack_compute_instance_v2" "vm" {
  count      = var.number
  name       = "${var.name}-${count.index}"
  image_name = var.image
  user_data  = file("script/boot.sh")

  stop_before_destroy = true

}

resource "openstack_networking_port_v2" "http" {
  count          = var.number
  name           = "port-http-${count.index}"
  network_id     = openstack_networking_network_v2.generic.id
  admin_state_up = true
  security_group_ids = [
    openstack_compute_secgroup_v2.http80.id,
    openstack_compute_secgroup_v2.http8080.id,

  ]

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.http.id
  }
}


resource "openstack_compute_secgroup_v2" "http80" {
  name        = "http"
  description = "Open input http port"
  rule {
    from_port   = 80
    to_port     = 80
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
}

resource "openstack_compute_secgroup_v2" "http8080" {
  name        = "http"
  description = "Open input http port"
  rule {
    from_port   = 80
    to_port     = 80
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
}


# Router creation
resource "openstack_networking_router_v2" "generic" {
  name                = "router"
  external_network_id = var.external_gateway
}

# Network creation
resource "openstack_networking_network_v2" "generic" {
  name = "network-generic"
}

#### HTTP SUBNET ####

# Subnet http configuration
resource "openstack_networking_subnet_v2" "http" {
  name            = var.network_http["subnet_name"]
  network_id      = openstack_networking_network_v2.generic.id
  cidr            = var.network_http["cidr"]
  dns_nameservers = var.dns_ip
}

# Router interface configuration
resource "openstack_networking_router_interface_v2" "http" {
  router_id = openstack_networking_router_v2.generic.id
  subnet_id = openstack_networking_subnet_v2.http.id
}


#
# Create loadbalancer
resource "openstack_lb_loadbalancer_v2" "http" {
  name          = "elastic_loadbalancer_http"
  vip_subnet_id = openstack_networking_subnet_v2.http.id
  depends_on    = [openstack_compute_instance_v2.vm]
}

# Create listener
resource "openstack_lb_listener_v2" "http" {
  name            = "listener_http"
  protocol        = "TCP"
  protocol_port   = 80
  loadbalancer_id = openstack_lb_loadbalancer_v2.http.id
  depends_on      = [openstack_lb_loadbalancer_v2.http]
}

# Set methode for load balance charge between instance
resource "openstack_lb_pool_v2" "http" {
  name        = "pool_http"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.http.id
  depends_on  = [openstack_lb_listener_v2.http]
}

# Add multip instances to pool
resource "openstack_lb_member_v2" "http" {
  count         = var.number
  address       = openstack_compute_instance_v2.vm[count.index].access_ip_v4
  protocol_port = 80
  pool_id       = openstack_lb_pool_v2.http.id
  subnet_id     = openstack_networking_subnet_v2.http.id
  depends_on    = [openstack_lb_pool_v2.http]
}

# Create health monitor for check services instances status
resource "openstack_lb_monitor_v2" "http" {
  name        = "monitor_http"
  pool_id     = openstack_lb_pool_v2.http.id
  type        = "TCP"
  delay       = 2
  timeout     = 2
  max_retries = 2
  depends_on  = [openstack_lb_member_v2.http]
}
