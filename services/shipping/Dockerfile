FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /shipping ./cmd/server

FROM alpine:3
COPY --from=build /shipping /shipping
EXPOSE 4002
CMD ["/shipping"]
