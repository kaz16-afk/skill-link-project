# ---------------------------------------------------------
# Bedrock Knowledge Base (RAG with Pinecone)
# ---------------------------------------------------------
resource "aws_bedrockagent_knowledge_base" "skill_link_kb" {
  provider = aws.virginia
  name     = "skill-link-kb-pine-cone"
  role_arn = "arn:aws:iam::<YOUR_ACCOUNT_ID>:role/SkillLinkManualKBExecutionRole"

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
      
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 1024
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "PINECONE"
    pinecone_configuration {
      connection_string = "https://<YOUR_PINECONE_INDEX_URL>"
      
      credentials_secret_arn = "arn:aws:secretsmanager:us-east-1:<YOUR_ACCOUNT_ID>:secret:pinecone-api-key-xxxxxx"
      
      field_mapping {
        metadata_field = "metadata"
        text_field     = "text"
      }
    }
  }

  tags = {
    project = "skill-link"
  }
}