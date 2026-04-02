[${AMI_USERNAME}]
secret = ${AMI_PASSWORD}
deny = 0.0.0.0/0.0.0.0
permit = ${AI_HOST}/255.255.255.255
permit = 127.0.0.1/255.255.255.255
read = all
write = all,originate
