import openai
import os
from dotenv import load_dotenv
load_dotenv()
openai.api_key = os.getenv("GROQ_API_KEY")

