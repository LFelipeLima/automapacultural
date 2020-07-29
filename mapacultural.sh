#!/bin/bash

# Script foi criado utilizando o tutorial do wiusmarques https://github.com/wiusmarques/mapasculturais

# Atualizando os repositórios de referência de sua máquina

sudo apt-get update
sudo apt-get upgrade

# Instalando as dependências diversas
sudo apt-get install git curl npm ruby2.5 ruby2.5-dev -y

# Atualizar referências para a versão de ruby 2.5
sudo update-alternatives --install /usr/bin/ruby ruby /usr/bin/ruby2.5 10
sudo update-alternatives --install /usr/bin/gem gem /usr/bin/gem2.5 10

# Instalando a versão stable mais nova do nodejs
sudo curl -sL https://deb.nodesource.com/setup_12.x -o nodesource_setup.sh
sudo bash nodesource_setup.sh
sudo apt install nodejs -y

# Instalando o postgresql e postgis
sudo apt-get install postgresql-10 postgresql-contrib postgis postgresql-10-postgis-2.4 postgresql-10-postgis-2.4-scripts -y

# Instalando o php7.2, php7.2-fpm e extensões do php utilizadas no sistema
sudo apt-get install php7.2 php7.2-gd php7.2-cli php7.2-json php7.2-curl php7.2-pgsql php-apcu php7.2-fpm imagemagick libmagickcore-dev libmagickwand-dev php7.2-imagick -y
sudo apt-get install php7.2-common php7.2-mbstring php7.2-xml php7.2-zip

# Instalando o nginx
sudo apt-get install nginx

# Instalando o gerenciador de dependências do PHP Composer
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer.phar

# Instalando pacote do zip
sudo apt-get install zip unzip

# Link simbólico do nodejs
sudo update-alternatives --install /usr/bin/node node /usr/bin/nodejs 10

# Instalando os minificadores de código Javascript e CSS: uglify-js, uglifycss e autoprefixer
sudo npm install -g uglify-js2 uglifycss autoprefixer
sudo update-alternatives --install /usr/bin/uglifyjs uglifyjs /usr/bin/uglifyjs2 10

# Instalando o SASS, utilizado para compilar os arquivos CSS
sudo gem install sass -v 3.4.22

# 3. Clonando o repositório
# Primeiro vamos criar o usuário que rodará a aplicação e que será proprietário do banco de dados, definindo sua home para /srv e colocando-o no grupo www-data:
sudo useradd -G www-data -d /srv/mapas -m mapas

# Clonando o repositório usando o usuário criando, então precisamos primeiro "logar" com este usuário:
sudo su - mapas
git clone https://github.com/mapasculturais/mapasculturais.git

# Agora vamos colocar o repositório na branch master.
# Colocar uma variável para escolher a branch
cd mapasculturais
git checkout master
git pull origin master

# Agora vamos instalar as dependências de PHP utilizando o Composer
cd ~/mapasculturais/src/protected/
composer.phar install
exit

# 4. Banco de Dados
# Primeiro vamos criar o usuário no banco de dados com o mesmo nome do usuário do sistema
sudo -u postgres psql -c "CREATE USER mapas"

# Agora vamos criar a base de dados para a aplicação com o mesmo nome do usuário
sudo -u postgres createdb --owner mapas mapas

# Criar as extensões necessárias no banco
sudo -u postgres psql -d mapas -c "CREATE EXTENSION postgis;"
sudo -u postgres psql -d mapas -c "CREATE EXTENSION unaccent;"

# Volte a "logar" com o usuário criado e importar o esquema da base de dados
sudo su - mapas
psql -f mapasculturais/db/schema.sql

# 5. Configurações de instalação
cp mapasculturais/src/protected/application/conf/config.template.php mapasculturais/src/protected/application/conf/config.php
exit

# Criando diretórios de log, files e estilo
sudo mkdir /var/log/mapasculturais
sudo chown mapas:www-data /var/log/mapasculturais

#Com o usuário criado, crie a pasta para os assets, para os uploads e para os uploads privados (arquivos protegidos, como anexos de inscrições em oportunidades)
sudo su - mapas
mkdir mapasculturais/src/assets
mkdir mapasculturais/src/files
mkdir mapasculturais/private-files
exit

#6. Configuração do nginx
# Muita atenção aqui, digite seu domínio ou IP fixo dependendo de qual for o seu caso.
clear
echo "Digite seu domínio ou IP fixo dependendo de qual for o seu caso:"
echo "Ex: meu.dominio.gov.br ou 1.1.1.1"
read dominio

# Precisamos criar o virtual host do nginx para a aplicação. Para isto crie, como root, o arquivo /etc/nginx/sites-available/mapas.conf
sudo cat > /etc/nginx/sites-available/mapas.conf <<EOF
server {
  set $site_name $dominio;

  listen *:80;
  server_name $site_name;
  access_log   /var/log/mapasculturais/nginx.access.log;
  error_log    /var/log/mapasculturais/nginx.error.log;

  index index.php;
  root  /srv/mapas/mapasculturais/src/;

  location / {
    try_files $uri $uri/ /index.php?$args;
  }
  
  location ~ /files/.*\.php$ {
    return 80;
  }
  

  location ~* \.(js|css|png|jpg|jpeg|gif|ico|woff)$ {
          expires 1w;
          log_not_found off;
  }

  location ~ \.php$ {
    try_files $uri =404;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass unix:/var/run/php/php7.2-fpm-$site_name.sock;
    client_max_body_size 0;
  }

  charset utf-8;
}

server {
  listen *:80;
  server_name $site_name;
  return 301 $scheme://$site_name$request_uri;
}
EOF

# Criando o link para habilitar o virtual host
sudo ln -s /etc/nginx/sites-available/mapas.conf /etc/nginx/sites-enabled/mapas.conf

# Remove o arquivo default da pasta /etc/nginx/sites-available/ e /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-available/default
sudo rm /etc/nginx/sites-enabled/default

# Configurações pool do php7.2-fpm: Cria o arquivo /etc/php/7.2/fpm/pool.d/mapas.conf
sudo cat > /etc/php/7.2/fpm/pool.d/mapas.conf <<EOF
[mapas]
listen = /var/run/php/php7.2-fpm-$dominio.sock
listen.owner = mapas
listen.group = www-data 
user = mapas
group = www-data
catch_workers_output = yes
pm = dynamic
pm.max_children = 10
pm.start_servers = 1
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
chdir = /srv/mapas
; php_admin_value[open_basedir] = /srv/mapas:/tmp
php_admin_value[session.save_path] = /tmp/
; php_admin_value[error_log] = /var/log/mapasculturais/php.error.log
; php_admin_flag[log_errors] = on
php_admin_value[display_errors] = 'stderr'
EOF

#7. Concluindo
# Precisamos popular o banco de dados com os dados iniciais e executar um script que entre outras coisas compila e minifica os assets, otimiza o autoload de classes do composer e roda atualizações do banco.
sudo su - mapas
psql -f mapasculturais/db/initial-data.sql
./mapasculturais/scripts/deploy.sh
exit
sudo service nginx restart
sudo service php7.2-fpm restart









