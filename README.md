# rabbit_test@
_Erlang application for testing RabbitMQ cluster and quorum queues._

---
## Usage
### Prerequisites
- Docker
- Erlang 25

### - Installation
```sh
# Example installation steps
git clone git@gitlab.int.favbet.tech:erlang/betting_line/bullet_front.git master
cd bullet_front
gmake
```

```sh
# Example local launch application steps
gmake ; _rel/rabbit_test_release/bin/rabbit_test_release console
```

```sh
# Example local launch Rabbit cluster steps
docker compose -f ./build/docker-compose.yaml down -v ; docker compose -f ./build/docker-compose.yaml up
```
