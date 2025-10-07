# This scripts gets a wordpress site up and running with valid ssl certs from letsencrypt at the given FQDN. 

# How-to written by Chris at https://technicallyrambling.calmatlas.com/installing-wordpress-to-rocky-linux/
# Incomplete instructions and inspiration found here: https://linuxways.net/red-hat/how-to-install-wordpress-on-rocky-linux-8/
# This script orginally written and tested on Rocky 9 GCP Optimized (Google Cloud Compute e2 medium instance)
# Additionally tested and modifed to work with Rocky 8 GCP Optimzed (Google Cloud Compute e2 medium instance)
# Pre-req - Valid dns record configured to point to this server
# Pre-req - Server needs internet access

# variables
SITENAME="technicallyrambling"
DOMAIN="calmatlas.com"
# email address needed for letsencrypt, if you comment the last part of this
EMAIL=chris@calmatlas.com

FQDN="$SITENAME.$DOMAIN"
WP_USER=wp_$SITENAME
WP_DB=wp_$SITENAME

# First update packages
sudo dnf update -y

# Rocky 8 on Google Cloud did not come with semanage installed. semanage comes from the policyutils-python-utils package
sudo dnf install policycoreutils-python-utils -y

#-----------------------------------------------------# 
# php
#-----------------------------------------------------# 
# The instructions from linuxways.net tell you to "reset the default php 7.2" without describing why or what that is. 
# The default appstream repo on a fresh install of rocky 8 will have php 7.2. At the time of this writing, the latest supported version is 8.
# If we needed the latest and greatest we'd install the remi repo here. As of this writing Rocky 9 defaults to PHP 8, while Rocky 8 defaults to PHP 7.2
# TODO - Check for current version and get it.

# Rocky 8 defaults to php 7.2 while rocky 9 defualts to php 8.  I won't be suing remi repos
# Set php 8 as desired version from appstream repo. These commands will fail on fresh install of rocky 9
sudo dnf module reset php -y
sudo dnf module enable php:8.0 -y

# Rocky 9 already has php 8 so let's just install from the appstream repo
sudo dnf install php php-cli php-json php-gd php-mbstring php-pdo php-xml php-mysqlnd php-pecl-zip -y

#----------------------------------------------------# 
# Database
#----------------------------------------------------# 
# install mariadb
sudo dnf install mariadb-server -y

# start and enable the mariadb
sudo systemctl enable --now mariadb

# Remove the mysql root password first if it exists. This is to allow the script to run more than once.
# To install a second instance of wordpress on the same server, for example. The root password will be changed
# There's probably a better way to do this.
sudo mysql --defaults-file=/root/wp_root.pass --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY ''"

# Create a databsae
sudo mysql --user="root" --execute "CREATE DATABASE $WP_DB"

# Create random password for the wordpress user - You'll need this later and will see it on script run.
wp_db_user_pass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32;echo;)

# Create the user
sudo mysql --user="root" --database="$WP_DB" --execute="CREATE USER '$WP_USER'@'localhost' IDENTIFIED BY '$wp_db_user_pass'"

# Grant the user privileges
sudo mysql --user="root" --database="$WP_DB" --execute="GRANT ALL ON $WP_DB.* TO '$WP_USER'@'localhost'"
sudo mysql --user="root" --database="$WP_DB" --execute="FLUSH PRIVILEGES"

# We should improve the security of the mariadb installation, the following command promps the user with questions
# sudo mysql_secure_installation

# The mysql_secure_installation is just a bash script. We can accomplish the same thing with the following lines
# Remover anonymous users
sudo mysql --user="root" --execute="DELETE FROM mysql.user WHERE User=''"
# allow root login from localhost only
sudo mysql --user="root" --execute="DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
# delete test database
sudo mysql --user="root" --execute="DROP DATABASE IF EXISTS test"
sudo mysql --user="root" --execute="DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"

# Generate a root password and save to a file
sudo sh -c 'wp_db_root_pass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32);
cat > /root/wp_root.pass << EOF
[client]
user=root
password=$wp_db_root_pass
EOF'
sudo chmod 400 /root/wp_root.pass

# Set root password
sudo mysql --user="root" --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY '$wp_db_root_pass'"
sudo mysql --user="root" --password="$wp_db_root_pass" --execute="FLUSH PRIVILEGES"

#----------------------------------------------------# 
# Webserver and wordpress files
#----------------------------------------------------# 
# Install apache and mod_ssl for 443
sudo dnf install httpd mod_ssl -y

# enable apache server
sudo systemctl enable --now httpd

# Download the latest worpdress
curl https://wordpress.org/latest.tar.gz --output ~/wordpress.tar.gz

# Extract the wordpress files to apache directory
sudo tar -xzf ~/wordpress.tar.gz -C /var/www/html
sudo mv /var/www/html/wordpress /var/www/html/$SITENAME

# give apapche ownership to wordpress
sudo chown -R apache:apache /var/www/html/$SITENAME

# set permissions to wordpress
sudo chmod -R 775 /var/www/html/$SITENAME

#selinux - give httpd rights to html folder
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/$SITENAME(/.*)?"
sudo restorecon -Rv /var/www/html/

# Create an apache virtual host file to point to the wordpress install
# We're writing it to the home directory of whoever ran the script first
cat > ~/$SITENAME.conf << EOF
<VirtualHost *:80>
  ServerName $FQDN
  Redirect permanent / https://$FQDN/
</VirtualHost>

<VirtualHost *:443>
  ServerName $FQDN

  ServerAdmin root@localhost
  DocumentRoot /var/www/html/$SITENAME
  ErrorLog /var/log/httpd/wordpress_error.log
  CustomLog /var/log/httpd/wordpress_access.log common

  <Directory "/var/www/html/$SITENAME">
    Options Indexes FollowSymLinks
    AllowOverride all
    Require all granted
  </Directory>

  SSLCertificateFile /etc/pki/tls/certs/localhost.crt
  SSLCertificateKeyFile /etc/pki/tls/private/localhost.key

</VirtualHost>
EOF

# Move the file we just created and give it the appropriate permissions
sudo chown root:root ~/$SITENAME.conf
sudo mv ~/$SITENAME.conf /etc/httpd/conf.d/

#selinux - label the conf file as a system file.
sudo semanage fcontext -a -t httpd_config_t -s system_u /etc/httpd/conf.d/$SITENAME.conf
sudo restorecon -Fv /etc/httpd/conf.d/$SITENAME.conf

# reset apache
sudo systemctl restart httpd

#----------------------------------------------------# 
# Security
#----------------------------------------------------# 

# open firewall ports
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# Additional selinux rules - files relabeled as needed above
# Without this setting the plugin and theme page does not work
sudo setsebool -P httpd_can_network_connect 1

# Configure letsencrypt for a cert - this requires that your DNS settings are already done. 
# Install epel repo
sudo dnf install epel-release -y

# Install certbot
sudo dnf install certbot python3-certbot-apache -y

# Retrieve and install the first cert.
sudo certbot --apache --non-interactive --agree-tos -m $EMAIL --domain $FQDN

# Disable rocky default welcome page
sudo sed -i'' 's/^\([^#]\)/#\1/g' /etc/httpd/conf.d/welcome.conf

# Disable directory browsing
sudo sed -i'' 's/Options Indexes/Options/g' /etc/httpd/conf/httpd.conf

#----------------------------------------------------# 
#  Output
#----------------------------------------------------# 
# Give username and password
echo ""
echo "Navigate to your site in a browser and use the following information"
echo "Database: $WP_DB"
echo "Wordpress User: $WP_USER"
echo "Password: $wp_db_user_pass"
echo ""
echo "Copy this info. You won't see it again."