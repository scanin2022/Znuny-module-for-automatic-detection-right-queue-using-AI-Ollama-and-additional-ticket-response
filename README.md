# Znuny-module-for-automatic-detection-right-queue-using-AI-Ollama-and-additional-ticket-response
Znuny module for automatic detection right queue using AI (Ollama) and additional ticket response

1. First of all you need to start your ollama server, change two strings of text in the source code: XXX.XXX.XXX.XXX to the IP address of your ollam server.
2. Correct in the source code two prompts: first prompt choose right queue, you need in prompt describe your departments using their numbers, which are stored in the Znuni database. You can retrieve them from the database using the following query (for POSTGRESS):

SELECT DISTINCT
    q.id AS queue_id,
    q.name AS queue_name,
    COUNT(t.id) AS ticket_count
FROM
    ticket t
JOIN
    queue q ON t.queue_id = q.id
WHERE
    t.create_time >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY
    q.id, q.name
ORDER BY
    ticket_count DESC;
    
3. Second prompt help to answer the question in ticket, correct it if you want.

4. Adding to Znuny this module by standart official manual, no need to set any variables. Action for module: new tickets or other reason
