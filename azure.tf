terraform {
  required_version = ">=1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  default = "East US 2"
    # default = "Central India"
}

variable "resource_group_name" {
  default = "sam-arc-demo-rg"
}

variable "admin_username" {
  default = "azureuser"
}

variable "tenant_id" {
    default = "80e7f9fe-6278-454e-9aec-1b8003a52639"
}

variable "subscription_id" {
    default = "63ef5cef-fb03-487b-9b40-80b838574496"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}


resource "azurerm_virtual_network" "vnet" {
  name                = "sam-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "sam-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "sam-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku = "Standard"
}

resource "azurerm_network_interface" "nic" {
  name                = "sam-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    public_ip_address_id          = azurerm_public_ip.pip.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "sam-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "allow-ssh"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "sam-linux-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  size                = "Standard_D2as_v5"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = {
    environment = "sam-demo"
  }
}

resource "azurerm_virtual_machine_extension" "install_software" {
  name                 = "install-software"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  settings = <<SETTINGS
{
  "commandToExecute": "sudo apt update && sudo apt install -y nginx apache2"
}
SETTINGS
}

data "azurerm_subscription" "current" {}

resource "azurerm_virtual_machine_extension" "arc_onboarding" {
  name                 = "arc-onboarding"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  depends_on = [
    azurerm_virtual_machine_extension.install_software
  ]

  settings = <<SETTINGS
{
  "commandToExecute": "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash && curl -sL https://aka.ms/azcmagent | sudo bash && sudo azcmagent connect --resource-group ${azurerm_resource_group.rg.name} --tenant-id ${var.tenant_id} --location ${var.location} --subscription-id ${data.azurerm_subscription.current.subscription_id}"
}
SETTINGS
}

output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

