# EpicBook – Production-Ready Docker Deployment

This project demonstrates how I took an existing Node.js application and deployed it as a production-style containerized stack on an AWS EC2 virtual machine.

The focus of this project is not the development of the EpicBook application itself, but the DevOps work required to understand, containerize, configure, secure, operate, and deploy the application in a repeatable way.

---

## Original Application

The EpicBook application source was originally created by:

https://github.com/pravinmishraaws/theepicbook

This repository contains my DevOps implementation around the application, including:

- Docker containerization
- Docker Compose orchestration
- Nginx reverse proxy
- Environment and secret management
- MySQL persistence
- Database initialization
- Health checks
- Structured logging
- Log persistence
- Log rotation
- AWS EC2 deployment
- Network hardening

---

## Architecture

```text
                        INTERNET
                            |
                            | HTTP :80
                            v
                    AWS Security Group
                            |
                            v
                  +-------------------+
                  |       Nginx       |
                  |   Reverse Proxy   |
                  |       :80         |
                  +---------+---------+
                            |
                      Docker Network
                            |
                            v
                  +-------------------+
                  |     EpicBook      |
                  | Node.js / Express |
                  |      :8080        |
                  +---------+---------+
                            |
                      Docker Network
                            |
                            v
                  +-------------------+
                  |       MySQL       |
                  |       :3306       |
                  +---------+---------+
                            |
                            v
                  Persistent Docker Volume
```

Only Nginx is exposed publicly.

The EpicBook application and MySQL database communicate internally through the Docker network.

---

## Technologies Used

- AWS EC2
- Ubuntu Linux
- Docker
- Docker Compose
- Nginx
- Node.js
- Express
- Express Handlebars
- Sequelize
- MySQL
- Git
- GitHub
- OpenSSL

---

## Application Analysis

Before containerizing the application, I first inspected the repository to understand how the application actually runs.

I reviewed files such as:

```text
package.json
server.js
models/index.js
config/config.json
```

From that inspection, I identified:

- **Node.js** as the application runtime
- **Express** as the web framework
- **Express Handlebars** as the server-side template engine
- **Sequelize** as the ORM
- **mysql2** as the MySQL database driver
- **MySQL** as the database
- `server.js` as the application entry point
- `npm start` as the startup command
- port `8080` as the default application port
- `NODE_ENV` as the environment selector
- `JAWSDB_URL` as the production database connection variable

This helped me design the deployment based on the application's actual requirements rather than assuming that the application had separate frontend and backend services.

---

## Container Architecture

The Docker Compose stack contains three main services:

1. Nginx
2. EpicBook application
3. MySQL database

---

## 1. Nginx Reverse Proxy

Nginx acts as the public entry point to the application.

It listens on:

```text
Port 80
```

and forwards incoming requests to:

```text
app:8080
```

inside the Docker network.

The EpicBook application is therefore not directly exposed to the internet.

The request flow is:

```text
Internet
   |
   v
Nginx :80
   |
   v
EpicBook :8080
   |
   v
MySQL :3306
```

Docker service discovery allows Nginx to communicate with the application using:

```text
app:8080
```

instead of relying on a hard-coded container IP address.

---

## 2. EpicBook Application

The EpicBook container runs the Node.js and Express application.

The application container:

- uses a multi-stage Docker build
- installs production dependencies using `npm ci --omit=dev`
- runs using the built-in non-root `node` user
- listens internally on port `8080`
- connects to MySQL through Docker networking
- uses production environment variables
- emits structured HTTP request logs
- includes an HTTP health check

The application is not directly published on the EC2 host.

Its port is only available inside the Docker network.

---

## 3. MySQL Database

The MySQL service provides the database used by EpicBook.

The database:

- runs inside its own container
- is not exposed publicly
- uses a persistent named Docker volume
- initializes the EpicBook schema automatically
- seeds author and book data
- includes a database health check
- uses environment variables for credentials

---

## Docker Multi-Stage Build

The application Dockerfile uses a multi-stage build.

### Stage 1 – Dependencies


Using:


helps provide a reproducible dependency installation based on `package-lock.json` while excluding development-only packages.

---

### Stage 2 – Runtime

```dockerfile
FROM node:22-alpine AS runtime

WORKDIR /app

COPY --from=dependencies /app/node_modules ./node_modules

COPY --chown=node:node . .

ENV NODE_ENV=production

USER node

EXPOSE 8080

CMD ["npm", "start"]
```

The final runtime image contains only what is required to run the application.

The application runs as the non-root `node` user rather than as `root`.

---

## Environment and Secret Management

Production credentials are stored in:

```text
.env
```

The `.env` file is excluded from Git using `.gitignore`.

An `.env.example` file is included to document the required variables without exposing real credentials.

Example:

```env
NODE_ENV=production

MYSQL_DATABASE=bookstore
MYSQL_USER=epicbook_user
MYSQL_PASSWORD=replace_me
MYSQL_ROOT_PASSWORD=replace_me

JAWSDB_URL=mysql://epicbook_user:replace_me@db:3306/bookstore
```

The real `.env` file must never be committed to source control.

---

## Why the Database Host Is `db`

The original development configuration used:

```text
127.0.0.1
```

for the MySQL host.

That would not work correctly when EpicBook and MySQL are running in separate containers because:

```text
127.0.0.1
```

inside the EpicBook container refers to the EpicBook container itself.

Docker Compose provides internal DNS between services.

Because the database service is named:

```yaml
db:
```

the application can reach MySQL using:

```text
db:3306
```

This removes the need to hard-code container IP addresses.

---

## Database Initialization

The MySQL container automatically loads the SQL files during first-time database initialization.

The SQL files are mounted into:

```text
/docker-entrypoint-initdb.d/
```

in this order:

```text
01-schema.sql
02-authors.sql
03-books.sql
```

The execution order is important because books contain foreign-key references to authors.

The initialization flow is:

```text
Create database schema
        |
        v
Insert authors
        |
        v
Insert books
```

---

## Database Persistence

MySQL stores its database files in a named Docker volume:

```text
mysql_data
```

The volume is mounted to:

```text
/var/lib/mysql
```

inside the MySQL container.

This means database data survives container deletion and recreation.

### Persistence Test

Persistence was tested by first checking the database record counts.

Before container recreation:

```text
Books:   54
Authors: 53
```

The containers were then removed using:

```bash
docker compose down
```

The Docker volume remained available.

The stack was recreated using:

```bash
docker compose up -d
```

The database was checked again.

After container recreation:

```text
Books:   54
Authors: 53
```

This confirmed that the MySQL data survived container recreation successfully.

---

## Health Checks

Health checks were added to improve service readiness and startup ordering.

---

### MySQL Health Check

The MySQL health check verifies that the database is ready to accept connections.

Conceptually:

```text
MySQL container starts
        |
        v
Health check runs
        |
        v
MySQL becomes healthy
```

EpicBook waits for the database to become healthy before starting.

---

### EpicBook Health Check

The application health check performs an HTTP request against:

```text
http://127.0.0.1:8080/
```

inside the EpicBook container.

This allows Docker to verify that the application is actually responding to HTTP requests rather than only checking whether the Node.js process exists.

---

### Startup Dependency Flow

```text
MySQL starts
     |
     v
MySQL becomes healthy
     |
     v
EpicBook starts
     |
     v
EpicBook becomes healthy
     |
     v
Nginx starts
```

This provides a cleaner startup sequence for the stack.

---

## Structured Logging

Structured logging was implemented for both Nginx and the EpicBook application.

---

### Nginx Structured Logging

Nginx access logs are written in JSON format.

Example:

```json
{
  "time": "2026-09-13T01:11:27+00:00",
  "remote_addr": "150.254.159.67",
  "method": "GET",
  "uri": "/assets/img/5.png",
  "status": 304,
  "request_time": 0.001,
  "upstream_addr": "172.18.0.3:8080"
}
```

Nginx logs are written to both:

```text
Docker stdout
```

and:

```text
logs/nginx/
```

The bind-mounted log directory provides persistent proxy logs on the EC2 VM.

---

### EpicBook Structured Logging

Structured HTTP request logging was added to the Node.js application.

Example:

```json
{
  "timestamp": "2026-09-13T01:29:00.708Z",
  "level": "info",
  "service": "epicbook-app",
  "event": "http_request",
  "method": "GET",
  "path": "/",
  "status": 304,
  "duration_ms": 7.987
}
```

The structured logs make it easier to understand:

- request method
- request path
- HTTP status
- response duration
- service name
- event type
- timestamp

---

## Log Persistence

Nginx logs are persisted to the VM using a bind mount.

The container path:

```text
/var/log/nginx
```

is mapped to:

```text
./logs/nginx
```

on the host.

This means Nginx log files remain available even if the Nginx container is recreated.

---

## Docker Log Rotation

Docker log rotation is configured for the services.

```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

This prevents Docker-managed logs from growing indefinitely.

Each container log file is limited to approximately:

```text
10 MB
```

and Docker retains up to:

```text
3 files
```

per service.

This reduces the risk of application logs consuming all available disk space on the VM.

---

## Nginx Security Hardening

Nginx was configured with:

```nginx
server_tokens off;
```

This prevents the exact Nginx version from being exposed in normal HTTP response headers.

The reverse proxy also forwards useful client information to the application through headers such as:

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

---

## Network Security

The AWS Security Group was configured to expose only the required public ports.

### Publicly Accessible

```text
22  - SSH
80  - HTTP
```

SSH access is restricted to an authorized IP address rather than being open to the entire internet.

---

### Not Publicly Exposed

```text
8080 - EpicBook application
3306 - MySQL
33060 - MySQL internal protocol
```

The EpicBook application and database remain inside the Docker network.

This prevents users from bypassing Nginx and prevents direct internet access to the database.

---

## Docker Networking

Docker Compose creates an internal network for the project.

The containers communicate using Docker service names.

Example:

```text
Nginx
  |
  v
app:8080
  |
  v
db:3306
```

This provides service discovery without relying on manually configured container IP addresses.

---

## Repository Structure

```text
.
├── config/
├── db/
│   ├── BuyTheBook_Schema.sql
│   ├── author_seed.sql
│   └── books_seed.sql
├── models/
├── nginx/
│   └── default.conf
├── public/
├── routes/
├── views/
├── .dockerignore
├── .env.example
├── .gitignore
├── compose.yaml
├── Dockerfile
├── package.json
├── package-lock.json
├── server.js
└── README.md
```

Runtime files such as:

```text
.env
logs/
```

are excluded from Git.

---

## Running the Project

### Prerequisites

The host should have:

- Docker
- Docker Compose
- Git

---

### 1. Clone the Repository

```bash
git clone https://github.com/AbdulQuadri04/epicbook-production-docker-deployment.git
```

Enter the project directory:

```bash
cd epicbook-production-docker-deployment
```

---

### 2. Create the Environment File

Copy the example file:

```bash
cp .env.example .env
```

Edit the file:

```bash
nano .env
```

Replace the placeholder credentials with strong values.

---

### 3. Build and Start the Stack

```bash
docker compose up -d --build
```

---

### 4. Check Container Status

```bash
docker compose ps
```

Expected state:

```text
epicbook-db      healthy
epicbook-app     healthy
epicbook-nginx   running
```

---

### 5. Test the Application

From the host:

```bash
curl -I http://127.0.0.1
```

Expected response:

```text
HTTP/1.1 200 OK
Server: nginx
```

If deployed on a cloud VM with port 80 allowed, the application can be accessed through:

```text
http://PUBLIC-IP
```

---

## Viewing Logs

### Nginx Logs

```bash
docker compose logs nginx
```

Follow them live:

```bash
docker compose logs -f nginx
```

Persistent Nginx logs can also be viewed with:

```bash
tail -f logs/nginx/access.log
```

---

### Application Logs

```bash
docker compose logs app
```

Follow them live:

```bash
docker compose logs -f app
```

---

### Database Logs

```bash
docker compose logs db
```

---

## Stopping the Stack

Stop and remove the containers and project network:

```bash
docker compose down
```

The MySQL volume remains intact.

---

## Removing the Database Volume

If the database should also be deleted:

```bash
docker compose down -v
```

**Warning:** this removes the persistent MySQL volume and deletes the stored database data.

---

## Useful Docker Commands

Check running containers:

```bash
docker compose ps
```

View Docker images:

```bash
docker images
```

View Docker volumes:

```bash
docker volume ls
```

Rebuild the application:

```bash
docker compose build app
```

Restart the stack:

```bash
docker compose up -d
```

Inspect application health:

```bash
docker inspect epicbook-app --format '{{json .State.Health}}'
```

Check Docker logging configuration:

```bash
docker inspect epicbook-app --format '{{json .HostConfig.LogConfig}}'
```

---

## Production Verification

The deployment was tested for:

- successful Docker image build
- successful Docker Compose deployment
- MySQL initialization
- SQL seed execution
- application-to-database connectivity
- Nginx-to-application connectivity
- public HTTP access
- HTTP `200 OK`
- database persistence
- application health checks
- database health checks
- secret exclusion from Git
- internal-only application port
- internal-only database port
- structured Nginx logging
- structured application logging
- persistent Nginx logs
- Docker log rotation
- container recreation
- service dependency ordering

---

## Troubleshooting Approach

One of the important lessons from this project was to troubleshoot the stack layer by layer.

The general approach used was:

```text
User reports problem
        |
        v
Check container status
        |
        v
Check Nginx logs
        |
        v
Check EpicBook logs
        |
        v
Check MySQL logs
        |
        v
Check service health
        |
        v
Check Docker networking
        |
        v
Identify the failing layer
```

Useful commands include:

```bash
docker compose ps
```

```bash
docker compose logs nginx
```

```bash
docker compose logs app
```

```bash
docker compose logs db
```

---

## Key DevOps Lessons

This project reinforced that containerization begins with understanding how an application actually operates.

Before writing a Dockerfile, I inspected the source repository to determine:

- what runtime the application needs
- how dependencies are installed
- how the application starts
- which port it listens on
- which database it requires
- how database configuration works
- which environment variables are required
- whether a frontend build step exists
- how services depend on one another

This helped me design the deployment based on the application's real requirements rather than simply copying a generic Docker configuration.

The project strengthened my understanding of:

- Docker image creation
- Docker multi-stage builds
- Docker Compose
- container networking
- Docker service discovery
- persistent volumes
- database initialization
- service health checks
- startup dependencies
- Nginx reverse proxying
- structured logging
- log persistence
- log rotation
- environment variables
- secret management
- AWS EC2 networking
- Security Groups
- production troubleshooting
- infrastructure hardening

---

## DevOps vs Application Development

One of the key learning points from this project was understanding the boundary between application development and DevOps responsibilities.

The application developer is primarily concerned with areas such as:

```text
business logic
application features
routes
database models
UI development
```

The DevOps focus is more operational:

```text
How does the application start?

Which runtime does it need?

Which dependencies are required?

Which ports does it use?

Which external services does it depend on?

How should secrets be provided?

How should the application be containerized?

How should traffic reach it?

How do we know it is healthy?

Where are the logs?

How does data persist?

How do we troubleshoot failures?

How do we deploy it safely?
```

This project helped reinforce that a DevOps engineer does not necessarily need to build the application from scratch, but must understand enough about the application to run it reliably in production.

---

## Future Improvements

Possible future improvements include:

### HTTPS / TLS

Add a domain name and configure HTTPS using:

- Let's Encrypt
- Certbot
- Nginx TLS configuration

This would allow the application to use:

```text
https://
```

instead of plain HTTP.

---

### CI/CD

A GitHub Actions pipeline could automate the deployment process.

Possible flow:

```text
Developer pushes code
        |
        v
GitHub Actions
        |
        v
Run validation/tests
        |
        v
Build Docker image
        |
        v
Push image to container registry
        |
        v
Connect securely to EC2
        |
        v
Deploy updated version
```

---

### Container Registry

Instead of building the application image directly on the production VM, future deployments could use:

- Docker Hub
- Amazon ECR
- GitHub Container Registry

The VM would then pull versioned production images.

---

### Centralized Monitoring and Logging

The structured JSON logs created in this project could later be forwarded to platforms such as:

- Amazon CloudWatch
- Grafana Loki
- Elasticsearch / Logstash / Kibana
- Splunk

---

### Dedicated Health Endpoints

The application currently uses the homepage for its HTTP health check.

A future version could provide dedicated endpoints such as:

```text
/health
/ready
```

These could separately report application liveness and dependency readiness.

---

## Author

**AbdulQuadri Olamilekan**

DevOps / Cloud Engineering

GitHub:

https://github.com/AbdulQuadri04
```bash
npm ci --omit=dev
```
```dockerfile
FROM node:22-alpine AS dependencies
This stage installs the production dependencies required by the application.
