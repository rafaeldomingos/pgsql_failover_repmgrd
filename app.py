from flask import Flask, request, jsonify
import psycopg2
from psycopg2 import sql
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

# Configurações do banco de dados
DB_NAME = "teste"
DB_USER = "postgres"
DB_PASS = ""
DB_HOST = "172.20.30.199"
DB_PORT = "5432"

# Conexão com o banco de dados
def get_db_connection():
    conn = psycopg2.connect(database=DB_NAME, user=DB_USER, password=DB_PASS, host=DB_HOST, port=DB_PORT)
    return conn

# Criação da tabela caso não exista
def create_table():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS pessoas (
            id SERIAL PRIMARY KEY,
            nome VARCHAR(255),
            cpf VARCHAR(11)
        );
    """)
    conn.commit()
    cur.close()
    conn.close()

create_table()

@app.route('/pessoas', methods=['POST'])
def insert_pessoa():
    conn = get_db_connection()
    cur = conn.cursor()
    nome = request.json['nome']
    cpf = request.json['cpf']
    cur.execute("INSERT INTO pessoas (nome, cpf) VALUES (%s, %s) RETURNING *;", (nome, cpf))
    pessoa = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    return jsonify(pessoa), 201

@app.route('/pessoas', methods=['GET'])
def get_pessoas():
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM pessoas;")
    pessoas = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify(pessoas)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')

