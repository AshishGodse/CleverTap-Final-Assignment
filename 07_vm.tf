resource "azurerm_public_ip" "pubip" {
  count                = var.vm_count
  name                 = "${var.project_name_prefix}vm-pubip-${count.index + 1}"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  allocation_method    = "Static"
}


resource "azurerm_network_interface" "nic" {
  count                = var.vm_count
  name                 = "${var.project_name_prefix}-vm-nic-${count.index + 1}"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app-snet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ips[count.index]
    public_ip_address_id          = azurerm_public_ip.pubip[count.index].id
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "ct-dev-app-vm-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "allow-http"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  

}

resource "azurerm_network_interface_security_group_association" "nsg-association" {
  count = var.vm_count
  network_interface_id      = azurerm_network_interface.nic[count.index].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  count                = var.vm_count
  name                 = "${var.project_name_prefix}vm-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.rg.name
  location             = azurerm_resource_group.rg.location
  size                 = var.vm_size
  admin_username       = var.vm_username
  admin_password       = var.vm_password # Use a secure password or SSH key
  zone                 = count.index + 1 # Specify the availability zone
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.nic[count.index].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  connection {
      type     = "ssh"
      user     = var.vm_username
      password = var.vm_password
      host     = self.public_ip_address
    }

  provisioner "file" {
    source      = "./Payload/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Installing Docker'",
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable'",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce",
      "sudo docker run hello-world",
      "sudo apt install -y docker-compose",
      "sudo chmod +777 /var/run/docker.sock",
      "sudo groupadd docker",
      "sudo docker swarm init",
      "sudo usermod -aG docker $USER",
      # "newgrp - docker",
      "echo 'Docker installation completed successfully. Please log out and log back in to apply the group changes.'",
      
      "echo 'Configuring proxy server...'",
      "PRIVATE_IP=$(hostname -I | awk '{print $1}')",
      "NGINX_CONF='/tmp/login-app2/nginx/nginx.conf'",
      "sed -i 's/server_name/server_name $PRIVATE_IP/g' $NGINX_CONF",
      "echo 'Building and running login-app1...'",
      "cd /tmp/login-app1/",
      "echo 'Proxy server configured successfully.'",

      "cd /tmp/login-app2/backend",
      "sudo docker build -t ctapp/backend:latest .",
      "cd /tmp/login-app2/frontend",
      "sudo docker build -t ctapp/frontend:latest .",
      "cd /tmp/login-app2",
      "sudo docker stack deploy -c docker-compose.yml ctapp",
      "echo 'login-app1 is running on port 80'",
      "exit"
    ]
}
depends_on = [ azurerm_mysql_flexible_database.mysql_db ]
}
