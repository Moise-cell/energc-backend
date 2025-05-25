from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg2
from psycopg2.extras import RealDictCursor
import os
from dotenv import load_dotenv
import logging

# Chargement des variables d'environnement
load_dotenv()

# Configuration du logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Configuration de la base de données
def get_db_connection():
    return psycopg2.connect(
        os.getenv('DATABASE_URL'),
        cursor_factory=RealDictCursor
    )

# Route de santé
@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({"status": "ok"})

# Route pour obtenir les dernières données d'un appareil
@app.route('/api/data/<device_id>/latest', methods=['GET'])
def get_latest_data(device_id):
    api_key = request.headers.get('x-api-key')
    if api_key != os.getenv('API_KEY'):
        return jsonify({"error": "Unauthorized"}), 401

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT * FROM device_data 
            WHERE device_id = %s 
            ORDER BY timestamp DESC 
            LIMIT 1
        """, (device_id,))
        
        data = cur.fetchone()
        cur.close()
        conn.close()

        if data:
            return jsonify(dict(data))
        return jsonify({"error": "No data found"}), 404

    except Exception as e:
        logger.error(f"Error fetching data: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# Route pour enregistrer de nouvelles données
@app.route('/api/data', methods=['POST'])
def save_data():
    api_key = request.headers.get('x-api-key')
    if api_key != os.getenv('API_KEY'):
        return jsonify({"error": "Unauthorized"}), 401

    try:
        data = request.json
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            INSERT INTO device_data (
                device_id, voltage, current1, current2, 
                energy1, energy2, relay1_status, relay2_status
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING *
        """, (
            data['device_id'],
            data['voltage'],
            data['current1'],
            data['current2'],
            data['energy1'],
            data['energy2'],
            data['relay1_status'],
            data['relay2_status']
        ))
        
        new_data = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        return jsonify(dict(new_data)), 201

    except Exception as e:
        logger.error(f"Error saving data: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port) 