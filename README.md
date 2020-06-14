# vagrant-prestashop

## Installation

    git clone https://github.com/estribiyo/vagrant-prestashop.git
    cd vagrant-prestashop

Change version of PrestaShop you want in file `bootstrap.sh` (`PRESTAVERSION=1.6.1.x`) ant then...

    vagrant up --provision

## How to use

First load virtualization

    vagrant up

Then... access URL:

    http://prestashop.lan

Admin:

    http://prestashop.lan/admin-dev

User/password is set on provisioning... access site and go on.

Shared folder of actual installation are on `/yourpath/vagrant-prestashop/sites/prestashop.lan`