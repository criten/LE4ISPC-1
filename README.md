# le4ispconfig
Lets Encrypt for ISP Config

This was based on code by Hj Ahmad Rasyid Hj Ismail at https://github.com/ahrasis/LE4ISPC

Main differences with my version
 * Not reliant on dpkg, uses systemctl for compatibility with CentOS & Debian
 * A help menu via command line argument `-h`
 * No auto update mechanism as this is potentially a remote code execution exploit
 * Validation against `hostname -f` - lets not poll Lets Encrypt unless your hostname is configured correctly
 * Overly complex crontab installer was replaced with 3 lines of code
 * Checks certificate expiry date and will only run 30 days or less from the expiry date
 * Use certbot --webroot if the httpd service is active, instead of bringing it down
 * Setup file permissions for the best possible security - to attempt to limit the possibility of reading the private key
 
 To install execute:
 ```
 wget -O /etc/ssl/le4ispc.sh https://raw.githubusercontent.com/criten/le4ispconfig/main/le4ispconfig.sh
 chmod +x /etc/ssl/le4ispc.sh
 /etc/ssl/le4ispc.sh
 ```
